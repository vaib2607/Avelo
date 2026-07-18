import Foundation

/// Orchestrates a Tally item-invoice posting for Sales/Purchase: computes
/// GST per line, builds the equivalent ledger voucher (party, sales/purchase
/// ledger, duty lines using the same fixed ledger codes a manually-entered
/// GST voucher would use — CGST_OUTPUT/SGST_OUTPUT/IGST_OUTPUT for sales,
/// CGST_INPUT/SGST_INPUT/IGST_INPUT for purchase, plus CESS), posts it
/// through the existing `VoucherService` unchanged, then persists the
/// structured item lines and records stock movements.
///
/// Ledger posting, item-line insertion, and stock movements all run inside
/// one outer `db.write` block: `SQLiteDatabase.write` is reentrant (tracks
/// nesting depth, only the outermost call opens/commits the transaction), so
/// `VoucherService.post`'s and `InventoryService.recordMovement`'s own
/// `db.write` calls join this transaction instead of committing separately.
/// A failure anywhere (e.g. selling more than is on hand) rolls back the
/// voucher too — no posted voucher can exist without its stock movement.
public final class ItemInvoiceService: Sendable {

    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
    }

    public struct ItemLineInput: Sendable {
        public let itemId: InventoryItem.ID
        public let quantity: ExactQuantity
        public let ratePaise: Int64

        public init(itemId: InventoryItem.ID, quantity: ExactQuantity, ratePaise: Int64) {
            self.itemId = itemId
            self.quantity = quantity
            self.ratePaise = ratePaise
        }

        public init(itemId: InventoryItem.ID, quantity: Int64, ratePaise: Int64) {
            self.init(itemId: itemId, quantity: try! ExactQuantity.whole(quantity), ratePaise: ratePaise)
        }
    }

    public struct Result: Sendable {
        public let voucher: Voucher
        public let itemLines: [VoucherItemLine]
        public let totalTaxableValuePaise: Int64
        public let totalCGSTPaise: Int64
        public let totalSGSTPaise: Int64
        public let totalIGSTPaise: Int64
        public let totalCESSPaise: Int64
        public let invoiceValuePaise: Int64
    }

    public func post(voucherTypeCode: VoucherType.Code,
                      date: Date,
                      partyAccountId: Account.ID,
                      salesOrPurchaseLedgerId: Account.ID,
                      items: [ItemLineInput],
                      narration: String = "",
                      billReferenceType: VoucherDraft.BillReferenceType? = nil,
                      billReferenceNumber: String? = nil,
                      in fy: FinancialYear) throws -> Result {
        guard voucherTypeCode == .sales || voucherTypeCode == .purchase else {
            throw AppError.businessRule("Item invoice mode only supports Sales and Purchase vouchers.")
        }
        guard !items.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "items", message: "Add at least one item line."))
        }

        // Fast user-facing rejection. The same facts are re-read inside the
        // write lock before the voucher number or any track row is created.
        try validateCurrentPostingState(
            voucherTypeCode: voucherTypeCode,
            date: date,
            partyAccountId: partyAccountId,
            salesOrPurchaseLedgerId: salesOrPurchaseLedgerId,
            items: items,
            financialYear: fy,
            database: db
        )

        let accountRepo = AccountRepository(db: db)
        guard let company = try CompanyRepository(db: db).findById(companyId) else {
            throw AppError.notFound("Company")
        }
        guard company.isInventoryEnabled else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
        guard let party = try accountRepo.findById(partyAccountId) else {
            throw AppError.notFound("Party account")
        }
        let groups = try AccountGroupRepository(db: db).listForCompany(companyId)
        let policy = try AccountEligibilityPolicy.loading(db: db, companyId: companyId)
        let partyEligibility = policy.evaluate(
            account: party,
            for: .itemInvoiceParty(voucherTypeCode),
            company: company,
            groups: groups
        )
        guard partyEligibility.isEligible else {
            throw AppError.validation(.init(code: .voucherAccountInactive, field: "partyAccountId", message: partyEligibility.rejectionReason ?? "Party account is not eligible for this invoice."))
        }
        guard let tradeLedger = try accountRepo.findById(salesOrPurchaseLedgerId) else {
            throw AppError.notFound("Sales or purchase ledger")
        }
        let tradeEligibility = policy.evaluate(
            account: tradeLedger,
            for: voucherTypeCode == .sales ? .salesLedger : .purchaseLedger,
            company: company,
            groups: groups
        )
        guard tradeEligibility.isEligible else {
            throw AppError.validation(.init(code: .voucherAccountInactive, field: "salesOrPurchaseLedgerId", message: tradeEligibility.rejectionReason ?? "Trade ledger is not eligible for this invoice."))
        }
        let inventoryRepo = InventoryRepository(db: db)

        let companyStateCode = company.gstin.flatMap(GSTStateCode.code(forGSTIN:))
        let partyStateCode = party.gstin.flatMap(GSTStateCode.code(forGSTIN:)) ?? party.stateCode
        let supplyType = try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: companyStateCode, partyStateCode: partyStateCode)

        struct LineComputation {
            let item: InventoryItem
            let input: ItemLineInput
            let result: GSTInvoiceCalculator.LineResult
        }

        var computations: [LineComputation] = []
        var totalTaxable: Int64 = 0
        var totalCGST: Int64 = 0
        var totalSGST: Int64 = 0
        var totalIGST: Int64 = 0
        var totalCESS: Int64 = 0

        for input in items {
            guard !input.quantity.isZero else {
                throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Quantity must be greater than zero."))
            }
            guard let wholeQuantity = input.quantity.wholeValue else {
                throw AppError.validation(.init(code: .itemInvoiceQuantityUnsupported, field: "quantity", message: "Fractional item-invoice quantities are not yet supported."))
            }
            guard let item = try inventoryRepo.findItemById(input.itemId), item.companyId == companyId, item.isActive else {
                throw AppError.validation(.init(code: .inventoryItemUnavailable, field: "itemId", message: "Inventory item is missing, inactive, or belongs to another company."))
            }
            let result = try GSTInvoiceCalculator.computeLine(
                .init(quantity: wholeQuantity, ratePaise: input.ratePaise,
                      gstRateBps: item.gstRateBps, cessRateBps: item.gstCessRateBps, taxability: item.gstTaxability),
                supplyType: supplyType
            )
            computations.append(.init(item: item, input: input, result: result))
            totalTaxable = try CheckedMath.add(totalTaxable, result.taxableValuePaise, context: "summing item invoice taxable value")
            totalCGST = try CheckedMath.add(totalCGST, result.cgstPaise, context: "summing item invoice CGST")
            totalSGST = try CheckedMath.add(totalSGST, result.sgstPaise, context: "summing item invoice SGST")
            totalIGST = try CheckedMath.add(totalIGST, result.igstPaise, context: "summing item invoice IGST")
            totalCESS = try CheckedMath.add(totalCESS, result.cessPaise, context: "summing item invoice CESS")
        }

        let isSales = voucherTypeCode == .sales
        let totalTax = try CheckedMath.sum([totalCGST, totalSGST, totalIGST, totalCESS], context: "summing item invoice total tax")
        let invoiceValue = try CheckedMath.add(totalTaxable, totalTax, context: "summing item invoice value")

        var draftLines: [VoucherDraft.Line] = []
        var order = 0
        draftLines.append(.init(accountId: partyAccountId, amountPaise: invoiceValue, side: isSales ? .debit : .credit, lineOrder: order))
        order += 1
        draftLines.append(.init(accountId: salesOrPurchaseLedgerId, amountPaise: totalTaxable, side: isSales ? .credit : .debit, lineOrder: order))
        order += 1

        func appendDutyLine(code: String, amountPaise: Int64) throws {
            guard amountPaise > 0 else { return }
            guard let account = try accountRepo.findByCode(code, companyId: companyId) else {
                throw AppError.businessRule("GST ledger '\(code)' is missing for this company.")
            }
            draftLines.append(.init(accountId: account.id, amountPaise: amountPaise, side: isSales ? .credit : .debit, lineOrder: order))
            order += 1
        }
        try appendDutyLine(code: isSales ? "CGST_OUTPUT" : "CGST_INPUT", amountPaise: totalCGST)
        try appendDutyLine(code: isSales ? "SGST_OUTPUT" : "SGST_INPUT", amountPaise: totalSGST)
        try appendDutyLine(code: isSales ? "IGST_OUTPUT" : "IGST_INPUT", amountPaise: totalIGST)
        try appendDutyLine(code: "CESS", amountPaise: totalCESS)

        let draft = VoucherDraft(
            mode: .create,
            entryMode: .itemInvoice,
            voucherTypeCode: voucherTypeCode,
            date: date,
            partyAccountId: partyAccountId,
            billReferenceType: billReferenceType,
            billReferenceNumber: billReferenceNumber,
            narration: narration,
            lines: draftLines
        )

        var voucher: Voucher!
        var itemLines: [VoucherItemLine] = []
        try db.write { tx in
            try validateCurrentPostingState(
                voucherTypeCode: voucherTypeCode,
                date: date,
                partyAccountId: partyAccountId,
                salesOrPurchaseLedgerId: salesOrPurchaseLedgerId,
                items: items,
                financialYear: fy,
                database: tx
            )
            voucher = try VoucherService(db: tx, companyId: companyId).postInCurrentTransaction(
                draft: draft,
                in: fy,
                workflow: nil,
                recordAudit: false
            ).voucher

            itemLines = computations.enumerated().map { (idx, c) in
                VoucherItemLine(
                    companyId: companyId,
                    voucherId: voucher.id,
                    itemId: c.item.id,
                    quantity: c.input.quantity,
                    ratePaise: c.input.ratePaise,
                    taxableValuePaise: c.result.taxableValuePaise,
                    hsnCode: c.item.hsnCode,
                    gstRateBps: c.item.gstRateBps,
                    cgstPaise: c.result.cgstPaise,
                    sgstPaise: c.result.sgstPaise,
                    igstPaise: c.result.igstPaise,
                    cessPaise: c.result.cessPaise,
                    lineOrder: idx
                )
            }
            try VoucherItemLineRepository(db: tx).insertBatch(itemLines)

            // The invoice owns the outer transaction and its one composite
            // audit event. Reuse transaction-scoped inventory posting so
            // authoritative valuation is republished without a second audit.
            let inventoryService = InventoryService(db: tx, companyId: companyId)
            for (index, computation) in computations.enumerated() {
                let evidence = itemLines[index]
                let movementType: InventoryItem.MovementType = isSales ? .stockOut : .stockIn
                let totalValue = isSales ? 0 : computation.result.taxableValuePaise
                _ = try inventoryService.recordMovementInCurrentTransaction(
                    StockMovement(
                        companyId: companyId,
                        itemId: computation.item.id,
                        date: date,
                        movementType: movementType,
                        quantity: computation.input.quantity,
                        unitCostPaise: computation.input.ratePaise,
                        totalValuePaise: totalValue,
                        voucherId: voucher.id,
                        referenceVoucherNumber: voucher.number,
                        reason: "Item invoice \(voucher.number)"
                    ),
                    item: computation.item,
                    sourceItemLineId: evidence.id,
                    recordAudit: false,
                    transactionDatabase: tx
                )
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherPosted,
                entityType: "item_invoice",
                entityId: voucher.id.uuidString,
                snapshotAfter: voucher
            )
        }

        ReportService.invalidateCache(companyId: companyId)

        return Result(
            voucher: voucher,
            itemLines: itemLines,
            totalTaxableValuePaise: totalTaxable,
            totalCGSTPaise: totalCGST,
            totalSGSTPaise: totalSGST,
            totalIGSTPaise: totalIGST,
            totalCESSPaise: totalCESS,
            invoiceValuePaise: invoiceValue
        )
    }

    /// Reverses an item invoice as one canonical composite mutation. Unlike
    /// the ledger-only voucher path it recreates invoice evidence and writes
    /// the matching opposite inventory movements before publishing one audit.
    public func reverse(_ voucherId: Voucher.ID, reason: String? = nil) throws -> Voucher {
        var reversal: Voucher?
        try db.write { tx in
            let voucherRepo = VoucherRepository(db: tx)
            guard let original = try voucherRepo.findById(voucherId), original.companyId == companyId else {
                throw AppError.notFound("Voucher")
            }
            guard !original.isReversal, original.status != .cancelled, !(try voucherRepo.hasReversal(for: voucherId)) else {
                throw AppError.businessRule("This item invoice cannot be reversed.")
            }
            let evidence = try VoucherItemLineRepository(db: tx).findForVoucher(voucherId)
            guard !evidence.isEmpty else { throw AppError.businessRule("Voucher is not an item invoice.") }
            let voucherService = VoucherService(db: tx, companyId: companyId)
            let originalLines = try LedgerLineRepository(db: tx).findForVoucher(voucherId)
            let created = try voucherService.createReversal(for: original, originalLines: originalLines, reason: reason)
            let flipped = voucherService.buildFlippedLines(from: originalLines, reversalId: created.id)
            try voucherRepo.insert(created)
            try LedgerLineRepository(db: tx).insertBatch(flipped)
            try voucherService.mirrorBillAllocation(from: original, to: created, originalLines: originalLines, workflowRepo: AccountingWorkflowsRepository(db: tx))

            let copiedEvidence = evidence.enumerated().map { index, line in
                VoucherItemLine(companyId: companyId, voucherId: created.id, itemId: line.itemId, quantity: line.exactQuantity,
                                ratePaise: line.ratePaise, taxableValuePaise: line.taxableValuePaise, hsnCode: line.hsnCode,
                                gstRateBps: line.gstRateBps, cgstPaise: line.cgstPaise, sgstPaise: line.sgstPaise,
                                igstPaise: line.igstPaise, cessPaise: line.cessPaise, lineOrder: index)
            }
            try VoucherItemLineRepository(db: tx).insertBatch(copiedEvidence)
            let originalMovements = try InventoryRepository(db: tx).listMovements(forVoucher: voucherId)
            guard originalMovements.count == copiedEvidence.count else {
                throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "inventory", message: "Item evidence and inventory movements do not reconcile."))
            }
            let inventory = InventoryService(db: tx, companyId: companyId)
            for (index, originalMovement) in originalMovements.enumerated() {
                guard let item = try InventoryRepository(db: tx).findItemById(originalMovement.itemId) else { throw AppError.notFound("Inventory item") }
                let reverseType: InventoryItem.MovementType = originalMovement.movementType == .stockIn ? .stockOut : .stockIn
                let reverse = StockMovement(companyId: companyId, itemId: originalMovement.itemId, date: created.date,
                                            movementType: reverseType, quantity: originalMovement.quantity,
                                            unitCostPaise: originalMovement.unitCostPaise,
                                            totalValuePaise: reverseType == .stockIn ? originalMovement.totalValuePaise : 0,
                                            voucherId: created.id, enteredUnit: originalMovement.enteredUnit,
                                            reversedMovementId: originalMovement.id, referenceVoucherNumber: created.number,
                                            reason: "Reversal of item invoice \(original.number)")
                _ = try inventory.recordMovementInCurrentTransaction(reverse, item: item, sourceItemLineId: copiedEvidence[index].id, recordAudit: false, transactionDatabase: tx)
            }
            try AuditService(db: tx, companyId: companyId).record(action: .voucherReversed, entityType: "item_invoice", entityId: created.id.uuidString, snapshotBefore: original, snapshotAfter: created, reason: reason)
            reversal = created
        }
        guard let reversal else { throw AppError.unexpected("Item invoice reversal did not complete.") }
        ReportService.invalidateCache(companyId: companyId)
        return reversal
    }

    /// Cancels an item invoice by creating its canonical composite reversal
    /// and marking the original cancelled inside one outer write scope.
    public func cancel(_ voucherId: Voucher.ID, reason: String, actor: String = "user") throws -> Voucher {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "reason", message: "Cancellation reason is required."))
        }
        var cancelled: Voucher?
        try db.write { tx in
            let repository = VoucherRepository(db: tx)
            guard let original = try repository.findById(voucherId), original.companyId == companyId else {
                throw AppError.notFound("Voucher")
            }
            guard original.status != .cancelled else { throw AppError.businessRule("This voucher has already been cancelled.") }
            let reversal = try self.reverse(voucherId, reason: "Cancellation: \(trimmed)")
            var updated = original
            updated.status = .cancelled
            updated.cancelledAt = reversal.createdAt
            updated.cancelledBy = actor
            updated.cancellationReason = trimmed
            updated.cancellationVoucherId = reversal.id
            updated.updatedAt = reversal.createdAt
            try repository.markCancelled(updated)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherCancelled,
                entityType: "item_invoice",
                entityId: updated.id.uuidString,
                snapshotBefore: original,
                snapshotAfter: updated,
                reason: trimmed
            )
            cancelled = updated
        }
        guard let cancelled else { throw AppError.unexpected("Item invoice cancellation did not complete.") }
        ReportService.invalidateCache(companyId: companyId)
        return cancelled
    }

    private func validateCurrentPostingState(voucherTypeCode: VoucherType.Code,
                                             date: Date,
                                             partyAccountId: Account.ID,
                                             salesOrPurchaseLedgerId: Account.ID,
                                             items: [ItemLineInput],
                                             financialYear: FinancialYear,
                                             database: SQLiteDatabase) throws {
        guard let currentFY = try FinancialYearRepository(db: database).findById(financialYear.id),
              currentFY.companyId == companyId,
              currentFY.contains(date: date) else {
            throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "date", message: "Item invoice date and financial year must belong to the active company."))
        }
        guard !currentFY.isLocked else {
            throw AppError.validation(.init(code: .canonicalTrackFYLocked, field: "date", message: "Financial year is locked."))
        }
        guard let company = try CompanyRepository(db: database).findById(companyId), company.isInventoryEnabled else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
        let accountRepo = AccountRepository(db: database)
        let groups = try AccountGroupRepository(db: database).listForCompany(companyId)
        let policy = try AccountEligibilityPolicy.loading(db: database, companyId: companyId)
        guard let party = try accountRepo.findById(partyAccountId),
              policy.evaluate(account: party, for: .itemInvoiceParty(voucherTypeCode), company: company, groups: groups).isEligible else {
            throw AppError.validation(.init(code: .voucherAccountInactive, field: "partyAccountId", message: "Party account is missing, inactive, or belongs to another company."))
        }
        let tradeContext: AccountSelectionContext = voucherTypeCode == .sales ? .salesLedger : .purchaseLedger
        guard let tradeLedger = try accountRepo.findById(salesOrPurchaseLedgerId),
              policy.evaluate(account: tradeLedger, for: tradeContext, company: company, groups: groups).isEligible else {
            throw AppError.validation(.init(code: .voucherAccountInactive, field: "salesOrPurchaseLedgerId", message: "Sales or purchase ledger is missing, inactive, or belongs to another company."))
        }
        let inventoryRepo = InventoryRepository(db: database)
        guard try inventoryRepo.hasActiveMainLocation(companyId: companyId) else {
            throw AppError.validation(.init(code: .inventoryLocationUnavailable, field: "location", message: "The active Main inventory location is unavailable."))
        }
        let companyStateCode = company.gstin.flatMap(GSTStateCode.code(forGSTIN:))
        let partyStateCode = party.gstin.flatMap(GSTStateCode.code(forGSTIN:)) ?? party.stateCode
        let supplyType = try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: companyStateCode, partyStateCode: partyStateCode)
        for input in items {
            guard !input.quantity.isZero else {
                throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Quantity must be greater than zero."))
            }
            guard let wholeQuantity = input.quantity.wholeValue else {
                throw AppError.validation(.init(code: .itemInvoiceQuantityUnsupported, field: "quantity", message: "Fractional item-invoice quantities are not yet supported."))
            }
            guard let item = try inventoryRepo.findItemById(input.itemId), item.companyId == companyId, item.isActive else {
                throw AppError.validation(.init(code: .inventoryItemUnavailable, field: "itemId", message: "Inventory item is missing, inactive, or belongs to another company."))
            }
            do {
                _ = try GSTInvoiceCalculator.computeLine(
                    .init(quantity: wholeQuantity, ratePaise: input.ratePaise, gstRateBps: item.gstRateBps, cessRateBps: item.gstCessRateBps, taxability: item.gstTaxability),
                    supplyType: supplyType
                )
            } catch {
                throw AppError.validation(.init(code: .itemInvoiceConfigurationInvalid, field: "items", message: "Item GST configuration is invalid for this invoice."))
            }
        }
    }
}
