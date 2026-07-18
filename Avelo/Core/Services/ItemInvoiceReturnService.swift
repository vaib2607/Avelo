import Foundation

/// Posts a physical partial return as a new Credit Note (sales return) or
/// Debit Note (purchase return). It never alters the original voucher or
/// movement; `reversal_of_inventory_id` is the durable return lineage.
public final class ItemInvoiceReturnService: Sendable {
    public struct Line: Sendable {
        public let sourceInventoryId: StockMovement.ID
        public let quantity: ExactQuantity

        public init(sourceInventoryId: StockMovement.ID, quantity: ExactQuantity) {
            self.sourceInventoryId = sourceInventoryId
            self.quantity = quantity
        }
    }

    public struct Request: Sendable {
        public let draft: VoucherDraft
        public let financialYear: FinancialYear
        public let lines: [Line]
        public let reason: String

        public init(draft: VoucherDraft, financialYear: FinancialYear, lines: [Line], reason: String) {
            self.draft = draft
            self.financialYear = financialYear
            self.lines = lines
            self.reason = reason
        }
    }

    public struct Result: Sendable {
        public let voucher: Voucher
        public let itemLines: [VoucherItemLine]
        public let movements: [StockMovement]
    }

    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
    }

    public func post(_ request: Request) throws -> Result {
        guard request.draft.voucherTypeCode == .creditNote || request.draft.voucherTypeCode == .debitNote else {
            throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "voucherType", message: "Item returns require a Credit Note or Debit Note."))
        }
        guard !request.lines.isEmpty, Set(request.lines.map(\.sourceInventoryId)).count == request.lines.count else {
            throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "lines", message: "Choose one or more distinct original inventory movements."))
        }
        guard !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "reason", message: "Return reason is required."))
        }
        var result: Result?
        try db.write { tx in
            result = try postInCurrentTransaction(request, database: tx)
        }
        guard let result else { throw AppError.unexpected("Item return did not produce a result.") }
        ReportService.invalidateCache(companyId: companyId)
        return result
    }

    private func postInCurrentTransaction(_ request: Request, database: SQLiteDatabase) throws -> Result {
        guard request.financialYear.companyId == companyId,
              request.financialYear.contains(date: request.draft.date),
              !request.financialYear.isLocked else {
            throw AppError.validation(.init(code: .canonicalTrackFYLocked, field: "date", message: "Return date must belong to an open company financial year."))
        }
        let inventoryRepo = InventoryRepository(db: database)
        guard try inventoryRepo.hasActiveMainLocation(companyId: companyId) else {
            throw AppError.validation(.init(code: .inventoryLocationUnavailable, field: "location", message: "The active Main inventory location is unavailable."))
        }

        let expectedSourceType: InventoryItem.MovementType = request.draft.voucherTypeCode == .creditNote ? .stockOut : .stockIn
        let resultType: InventoryItem.MovementType = request.draft.voucherTypeCode == .creditNote ? .stockIn : .stockOut
        let expectedOriginalVoucher: VoucherType.Code = request.draft.voucherTypeCode == .creditNote ? .sales : .purchase
        let itemRepo = VoucherItemLineRepository(db: database)
        let voucherRepo = VoucherRepository(db: database)
        let itemMasterRepo = InventoryRepository(db: database)

        struct Prepared {
            let source: StockMovement
            let sourceEvidence: VoucherItemLine
            let returnQuantity: ExactQuantity
            let restoredValuePaise: Int64
        }
        var prepared: [Prepared] = []
        for line in request.lines {
            guard !line.quantity.isZero, line.quantity.wholeValue != nil else {
                throw AppError.validation(.init(code: .itemInvoiceQuantityUnsupported, field: "quantity", message: "Partial item-invoice returns require a positive whole quantity."))
            }
            guard let source = try inventoryRepo.findMovement(id: line.sourceInventoryId),
                  source.companyId == companyId,
                  source.movementType == expectedSourceType,
                  let sourceVoucherId = source.voucherId,
                  let sourceVoucher = try voucherRepo.findById(sourceVoucherId),
                  sourceVoucher.voucherTypeCode == expectedOriginalVoucher else {
                throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "sourceInventoryId", message: "Return source does not match the required posted item invoice."))
            }
            guard let sourceItemLineId = try inventoryRepo.sourceItemLineId(for: source.id),
                  let evidence = try itemRepo.findById(sourceItemLineId), evidence.companyId == companyId, evidence.itemId == source.itemId else {
                throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "sourceInventoryId", message: "Return source has no valid item-invoice evidence."))
            }
            guard let item = try itemMasterRepo.findItemById(source.itemId), item.companyId == companyId, item.isActive else {
                throw AppError.validation(.init(code: .inventoryItemUnavailable, field: "sourceInventoryId", message: "Returned inventory item is unavailable."))
            }
            let prior = try inventoryRepo.listMovements(reversing: source.id)
            let priorQty = try prior.reduce(into: ExactQuantity.whole(0)) { total, movement in
                total = try ExactQuantity.add(total, movement.quantity, context: "summing already returned quantity")
            }
            let remainingQty = try ExactQuantity.subtract(source.quantity, priorQty, context: "calculating returnable quantity")
            guard try ExactQuantity.compare(line.quantity, remainingQty) != .orderedDescending else {
                throw AppError.validation(.init(code: .quantityExceedsStock, field: "quantity", message: "Return quantity exceeds the unreturned original quantity."))
            }
            let restoredValue: Int64
            if resultType == .stockIn {
                let priorValue = try CheckedMath.sum(prior.map(\.totalValuePaise), context: "summing already restored return value")
                let remainingValue = try CheckedMath.subtract(source.totalValuePaise, priorValue, context: "calculating returnable source value")
                restoredValue = try proratedValue(value: remainingValue, quantity: line.quantity, total: remainingQty)
            } else {
                restoredValue = 0
            }
            prepared.append(.init(source: source, sourceEvidence: evidence, returnQuantity: line.quantity, restoredValuePaise: restoredValue))
        }

        var returnDraft = request.draft
        returnDraft.entryMode = .itemInvoice
        let voucher = try VoucherService(db: database, companyId: companyId).postInCurrentTransaction(
            draft: returnDraft,
            in: request.financialYear,
            workflow: nil,
            recordAudit: false
        ).voucher

        var evidenceRows: [VoucherItemLine] = []
        var movements: [StockMovement] = []
        let inventoryService = InventoryService(db: database, companyId: companyId)
        for (index, line) in prepared.enumerated() {
            let evidence = proratedEvidence(line.sourceEvidence, quantity: line.returnQuantity, voucherId: voucher.id, order: index)
            evidenceRows.append(evidence)
            try VoucherItemLineRepository(db: database).insertBatch([evidence])
            guard let item = try inventoryRepo.findItemById(line.source.itemId) else { throw AppError.notFound("Inventory item") }
            let movement = StockMovement(
                companyId: companyId,
                itemId: line.source.itemId,
                date: returnDraft.date,
                movementType: resultType,
                quantity: line.returnQuantity,
                unitCostPaise: line.source.unitCostPaise,
                totalValuePaise: line.restoredValuePaise,
                voucherId: voucher.id,
                enteredUnit: line.source.enteredUnit,
                reversedMovementId: line.source.id,
                referenceVoucherNumber: voucher.number,
                reason: request.reason
            )
            _ = try inventoryService.recordMovementInCurrentTransaction(
                movement,
                item: item,
                sourceItemLineId: evidence.id,
                recordAudit: false,
                transactionDatabase: database
            )
            movements.append(movement)
        }
        try AuditService(db: database, companyId: companyId).record(
            action: .itemInvoiceReturnPosted,
            entityType: "item_invoice_return",
            entityId: voucher.id.uuidString,
            snapshotAfter: voucher,
            reason: request.reason
        )
        return .init(voucher: voucher, itemLines: evidenceRows, movements: movements)
    }

    private func proratedEvidence(_ source: VoucherItemLine, quantity: ExactQuantity, voucherId: Voucher.ID, order: Int) -> VoucherItemLine {
        VoucherItemLine(
            companyId: companyId, voucherId: voucherId, itemId: source.itemId, quantity: quantity,
            ratePaise: source.ratePaise,
            taxableValuePaise: (try? proratedValue(value: source.taxableValuePaise, quantity: quantity, total: source.exactQuantity)) ?? 0,
            hsnCode: source.hsnCode, gstRateBps: source.gstRateBps,
            cgstPaise: (try? proratedValue(value: source.cgstPaise, quantity: quantity, total: source.exactQuantity)) ?? 0,
            sgstPaise: (try? proratedValue(value: source.sgstPaise, quantity: quantity, total: source.exactQuantity)) ?? 0,
            igstPaise: (try? proratedValue(value: source.igstPaise, quantity: quantity, total: source.exactQuantity)) ?? 0,
            cessPaise: (try? proratedValue(value: source.cessPaise, quantity: quantity, total: source.exactQuantity)) ?? 0,
            lineOrder: order
        )
    }

    private func proratedValue(value: Int64, quantity: ExactQuantity, total: ExactQuantity) throws -> Int64 {
        guard try ExactQuantity.compare(quantity, total) != .orderedDescending else {
            throw AppError.validation(.init(code: .inventoryReturnInvalid, field: "quantity", message: "Return quantity exceeds source quantity."))
        }
        if try ExactQuantity.compare(quantity, total) == .orderedSame { return value }
        let first = try CheckedMath.multiply(value, quantity.numerator, context: "allocating partial return value")
        let numerator = try CheckedMath.multiply(first, total.denominator, context: "allocating partial return value")
        let denominator = try CheckedMath.multiply(quantity.denominator, total.numerator, context: "allocating partial return value")
        guard denominator > 0 else { throw AppError.businessRule("Partial return quantity is invalid.") }
        return numerator / denominator
    }
}
