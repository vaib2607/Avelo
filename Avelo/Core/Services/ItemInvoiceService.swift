import Foundation

/// Orchestrates a Tally item-invoice posting for Sales/Purchase: computes
/// GST per line, builds the equivalent ledger voucher (party, sales/purchase
/// ledger, duty lines using the same fixed ledger codes a manually-entered
/// GST voucher would use — CGST_OUTPUT/SGST_OUTPUT/IGST_OUTPUT for sales,
/// CGST_INPUT/SGST_INPUT/IGST_INPUT for purchase, plus CESS), posts it
/// through the existing `VoucherService` unchanged, then persists the
/// structured item lines and records stock movements.
///
/// Deliberately two separate database writes (ledger posting via
/// `VoucherService.post`, then item lines + stock movements) rather than one
/// atomic transaction spanning all three — matches how the rest of the app
/// already relates vouchers to inventory (`DemoCompanySeeder` posts a
/// voucher, then separately calls `InventoryService.recordMovement`).
///
/// ponytail: not atomic across accounting + stock — a crash between the two
/// writes could leave a posted voucher with no stock movement (item lines
/// audit trail still recorded either way). Upgrade path if this bites:
/// move stock recording inside `VoucherService.post`'s own transaction.
public final class ItemInvoiceService: Sendable {

    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
    }

    public struct ItemLineInput: Sendable {
        public let itemId: InventoryItem.ID
        public let quantity: Int64
        public let ratePaise: Int64

        public init(itemId: InventoryItem.ID, quantity: Int64, ratePaise: Int64) {
            self.itemId = itemId
            self.quantity = quantity
            self.ratePaise = ratePaise
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

        let accountRepo = AccountRepository(db: db)
        guard let company = try CompanyRepository(db: db).findById(companyId) else {
            throw AppError.notFound("Company")
        }
        guard let party = try accountRepo.findById(partyAccountId), party.companyId == companyId else {
            throw AppError.notFound("Party account")
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
            guard input.quantity > 0 else {
                throw AppError.validation(.init(code: .internal, field: "quantity", message: "Quantity must be greater than zero."))
            }
            guard let item = try inventoryRepo.findItemById(input.itemId), item.companyId == companyId else {
                throw AppError.notFound("Inventory item")
            }
            let result = try GSTInvoiceCalculator.computeLine(
                .init(quantity: input.quantity, ratePaise: input.ratePaise,
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
            voucherTypeCode: voucherTypeCode,
            date: date,
            partyAccountId: partyAccountId,
            billReferenceType: billReferenceType,
            billReferenceNumber: billReferenceNumber,
            narration: narration,
            lines: draftLines
        )

        let voucherService = VoucherService(db: db, companyId: companyId)
        let postResult = try voucherService.post(draft: draft, in: fy)
        let voucher = postResult.voucher

        let itemLines = computations.enumerated().map { (idx, c) in
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
        try VoucherItemLineRepository(db: db).insertBatch(itemLines)

        if company.isInventoryEnabled {
            let inventoryService = InventoryService(db: db, companyId: companyId)
            for c in computations {
                _ = try inventoryService.recordMovement(
                    itemId: c.item.id,
                    date: date,
                    type: isSales ? .stockOut : .stockIn,
                    quantity: c.input.quantity,
                    ratePaise: c.input.ratePaise,
                    voucherId: voucher.id,
                    notes: "Item invoice \(voucher.number)"
                )
            }
        }

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
}
