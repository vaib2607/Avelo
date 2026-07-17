import Foundation
import AppKit

public final class InvoicePDFService: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func exportTaxInvoicePDF(voucherId: Voucher.ID) throws -> Data {
        let voucherRepo = VoucherRepository(db: db)
        let companyRepo = CompanyRepository(db: db)
        let accountRepo = AccountRepository(db: db)
        let lineRepo = LedgerLineRepository(db: db)
<<<<<<< HEAD
        let inventoryRepo = InventoryRepository(db: db)
=======
>>>>>>> origin/main

        guard let voucher = try voucherRepo.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard voucher.voucherTypeCode == .sales || voucher.voucherTypeCode == .purchase else {
            throw AppError.businessRule("Tax invoice PDF is only available for Sales and Purchase vouchers.")
        }
        guard let company = try companyRepo.findById(voucher.companyId) else {
            throw AppError.notFound("Company")
        }

        let lines = try lineRepo.findForVoucher(voucherId)
        let party = try voucher.partyAccountId.flatMap { try accountRepo.findById($0) }
        let allAccounts = try accountRepo.listForCompany(voucher.companyId)
        let accountById = Dictionary(uniqueKeysWithValues: allAccounts.map { ($0.id, $0) })
<<<<<<< HEAD
        let visibleTotalPaise = try TaxInvoicePDFView.validateVisibleLineTotals(
            voucher: voucher,
            lines: lines,
            accountById: accountById
        )

        let taxBreakdown = try GSTService(db: db, companyId: voucher.companyId).voucherTaxBreakdown(voucherId: voucherId)
        let placeOfSupply = TaxInvoicePDFView.placeOfSupply(supplierGSTIN: company.gstin, partyGSTIN: party?.gstin)

        // Stock detail (AVL-P0-022 / Phase 2): item-invoice-mode postings
        // (`ItemInvoiceService`) persist structured `avelo_voucher_item_lines`
        // with HSN and per-line rate, so prefer that as the source of truth
        // when present. Older/manual postings have no item lines -- there is
        // no persisted link from a ledger line to a stock movement for those,
        // so fall back to rendering straight from the movements themselves.
        let itemLines = try VoucherItemLineRepository(db: db).findForVoucher(voucherId)
        let stockRows: [TaxInvoicePDFView.StockRow]
        if !itemLines.isEmpty {
            stockRows = try itemLines.map { line in
                let item = try inventoryRepo.findItemById(line.itemId)
                return TaxInvoicePDFView.StockRow(
                    itemName: item?.name ?? "Unknown item",
                    hsnCode: line.hsnCode,
                    quantityDisplay: String(line.quantity),
                    unit: item?.unit ?? "",
                    rateDisplay: Currency.formatPaise(line.ratePaise),
                    valueDisplay: Currency.formatPaise(line.invoiceValuePaise)
                )
            }
        } else {
            let movements = try inventoryRepo.listMovements(forVoucher: voucherId)
            stockRows = try movements.map { movement in
                let item = try inventoryRepo.findItemById(movement.itemId)
                return TaxInvoicePDFView.StockRow(
                    itemName: item?.name ?? "Unknown item",
                    hsnCode: item?.hsnCode,
                    quantityDisplay: movement.quantityDisplayString,
                    unit: movement.enteredUnit ?? item?.unit ?? "",
                    rateDisplay: Currency.formatPaise(movement.unitCostPaise),
                    valueDisplay: Currency.formatPaise(movement.totalValuePaise)
                )
            }
        }
=======
>>>>>>> origin/main

        let view = TaxInvoicePDFView(
            frame: NSRect(x: 0, y: 0, width: 595.2, height: 841.8),
            company: company,
            voucher: voucher,
            party: party,
            lines: lines,
<<<<<<< HEAD
            accountById: accountById,
            visibleTotalPaise: visibleTotalPaise,
            taxBreakdown: taxBreakdown,
            placeOfSupply: placeOfSupply,
            stockRows: stockRows
        )
        let pdfData = view.dataWithPDF(inside: view.bounds)
        return pdfData
    }

    public func recordExportSaved(voucherId: Voucher.ID, url: URL) throws {
        guard let voucher = try VoucherRepository(db: db).findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        do {
            try AuditService(db: db, companyId: voucher.companyId).record(
                action: .invoicePDFExported,
                entityType: "voucher",
                entityId: voucherId.uuidString,
                reason: url.lastPathComponent
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
=======
            accountById: accountById
        )
        return view.dataWithPDF(inside: view.bounds)
>>>>>>> origin/main
    }
}

private final class TaxInvoicePDFView: NSView {

<<<<<<< HEAD
    /// Whether a GSTIN-derivable recipient is in the same state as the
    /// supplier (CGST+SGST) or a different one (IGST). `nil` when the party
    /// has no GSTIN at all -- this pass covers registered (B2B) parties
    /// only; an unregistered/B2C party renders "Unregistered" and omits
    /// place of supply rather than guessing (AVL-P0-022 core B2B slice).
    enum PlaceOfSupply {
        case intraState(String)
        case interState(supplierState: String?, partyState: String)
    }

    struct StockRow {
        let itemName: String
        let hsnCode: String?
        let quantityDisplay: String
        let unit: String
        let rateDisplay: String
        let valueDisplay: String
    }

=======
>>>>>>> origin/main
    private let company: Company
    private let voucher: Voucher
    private let party: Account?
    private let lines: [LedgerLine]
    private let accountById: [Account.ID: Account]
<<<<<<< HEAD
    private let visibleTotalPaise: Int64
    private let taxBreakdown: GSTService.VoucherTaxBreakdown
    private let placeOfSupply: PlaceOfSupply?
    private let stockRows: [StockRow]
=======
>>>>>>> origin/main

    init(frame frameRect: NSRect,
         company: Company,
         voucher: Voucher,
         party: Account?,
         lines: [LedgerLine],
<<<<<<< HEAD
         accountById: [Account.ID: Account],
         visibleTotalPaise: Int64,
         taxBreakdown: GSTService.VoucherTaxBreakdown,
         placeOfSupply: PlaceOfSupply?,
         stockRows: [StockRow]) {
=======
         accountById: [Account.ID: Account]) {
>>>>>>> origin/main
        self.company = company
        self.voucher = voucher
        self.party = party
        self.lines = lines
        self.accountById = accountById
<<<<<<< HEAD
        self.visibleTotalPaise = visibleTotalPaise
        self.taxBreakdown = taxBreakdown
        self.placeOfSupply = placeOfSupply
        self.stockRows = stockRows
=======
>>>>>>> origin/main
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

<<<<<<< HEAD
    /// Derives place of supply by comparing GST state-code prefixes.
    /// Returns `nil` when the party has no GSTIN (unregistered/B2C party --
    /// explicitly out of scope for this pass). Does not reconcile against
    /// whichever CGST/SGST/IGST lines were actually posted; if those
    /// disagree with the GSTIN-derived state, both facts render as-is
    /// rather than one silently overriding the other.
    static func placeOfSupply(supplierGSTIN: String?, partyGSTIN: String?) -> PlaceOfSupply? {
        guard let partyGSTIN, let partyState = GSTStateCode.stateName(forGSTIN: partyGSTIN) else { return nil }
        let supplierState = supplierGSTIN.flatMap(GSTStateCode.stateName(forGSTIN:))
        if let supplierState, supplierState == partyState {
            return .intraState(partyState)
        }
        return .interState(supplierState: supplierState, partyState: partyState)
    }

=======
>>>>>>> origin/main
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { false }

<<<<<<< HEAD
    private var visibleLines: [(LedgerLine, Account)] {
        lines.compactMap { line -> (LedgerLine, Account)? in
            if let partyId = voucher.partyAccountId, line.accountId == partyId {
                return nil
            }
            guard let account = accountById[line.accountId] else { return nil }
            return (line, account)
        }
    }

    static func validateVisibleLineTotals(voucher: Voucher,
                                          lines: [LedgerLine],
                                          accountById: [Account.ID: Account]) throws -> Int64 {
        let visibleLineAmounts = lines.compactMap { line -> Int64? in
            if let partyId = voucher.partyAccountId, line.accountId == partyId {
                return nil
            }
            guard accountById[line.accountId] != nil else { return nil }
            return line.amountPaise
        }
        return try CheckedMath.sum(
            visibleLineAmounts,
            context: "summing invoice PDF visible line totals"
        )
    }

=======
>>>>>>> origin/main
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()

        let margin: CGFloat = 36
        let pageWidth = bounds.width - margin * 2
        var cursorY = bounds.height - margin

        func drawText(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .black, width: CGFloat? = nil, alignment: NSTextAlignment = .left) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: x, y: y, width: width ?? pageWidth, height: font.pointSize * 2.2)
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }

        func advance(_ spacing: CGFloat) {
            cursorY -= spacing
        }

        drawText(company.name, x: margin, y: cursorY - 24, font: .boldSystemFont(ofSize: 20))
        advance(30)
        if let line1 = company.addressLine1, !line1.isEmpty {
            drawText(line1, x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(14)
        }
        if let line2 = company.addressLine2, !line2.isEmpty {
            drawText(line2, x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(14)
        }
        let companyMeta = [company.city, company.state, company.pincode].compactMap { $0 }.joined(separator: ", ")
        if !companyMeta.isEmpty {
            drawText(companyMeta, x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(14)
        }
        if let gstin = company.gstin, !gstin.isEmpty {
            drawText("GSTIN: \(gstin)", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(14)
        }

        drawText("TAX INVOICE", x: margin, y: cursorY - 28, font: .boldSystemFont(ofSize: 16))
        drawText("Voucher: \(voucher.number)", x: bounds.width - margin - 220, y: cursorY - 28, font: .systemFont(ofSize: 11), width: 220, alignment: .right)
        advance(34)
        drawText("Date: \(DateFormatters.displayDate(voucher.date))", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
        if let party {
            drawText("Party: \(party.name)", x: margin + 180, y: cursorY - 18, font: .systemFont(ofSize: 11))
            if let gstin = party.gstin, !gstin.isEmpty {
                drawText("Party GSTIN: \(gstin)", x: margin + 350, y: cursorY - 18, font: .systemFont(ofSize: 11))
<<<<<<< HEAD
            } else {
                drawText("Party GSTIN: Unregistered", x: margin + 350, y: cursorY - 18, font: .systemFont(ofSize: 11))
            }
        }
        advance(18)
        switch placeOfSupply {
        case .intraState(let state):
            drawText("Place of Supply: \(state) (Intra-State)", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(20)
        case .interState(_, let partyState):
            drawText("Place of Supply: \(partyState) (Inter-State)", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11))
            advance(20)
        case nil:
            break
        }
=======
            }
        }
        advance(24)
>>>>>>> origin/main
        if !voucher.narration.isEmpty {
            drawText("Narration: \(voucher.narration)", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11), width: pageWidth)
            advance(20)
        }

        let columns: [(String, CGFloat)] = [
<<<<<<< HEAD
            ("Description", 300),
            ("HSN/SAC", 100),
=======
            ("Description", 220),
            ("HSN/SAC", 80),
            ("Qty", 50),
            ("Rate", 80),
>>>>>>> origin/main
            ("Amount", 90)
        ]
        let columnGap: CGFloat = 8
        var x = margin
        for (title, width) in columns {
            drawText(title, x: x, y: cursorY - 18, font: .boldSystemFont(ofSize: 10), width: width)
            x += width + columnGap
        }
        advance(20)
        NSColor.black.setStroke()
        let linePath = NSBezierPath()
        linePath.lineWidth = 0.6
        linePath.move(to: CGPoint(x: margin, y: cursorY - 4))
        linePath.line(to: CGPoint(x: bounds.width - margin, y: cursorY - 4))
        linePath.stroke()
        advance(12)

<<<<<<< HEAD
=======
        let visibleLines = lines.compactMap { line -> (LedgerLine, Account)? in
            if let partyId = voucher.partyAccountId, line.accountId == partyId {
                return nil
            }
            guard let account = accountById[line.accountId] else { return nil }
            return (line, account)
        }

>>>>>>> origin/main
        for (line, account) in visibleLines {
            let rowHeight: CGFloat = 22
            x = margin
            drawText(account.name, x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[0].1)
            x += columns[0].1 + columnGap
            drawText(line.taxCode ?? "", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[1].1)
            x += columns[1].1 + columnGap
<<<<<<< HEAD
            drawText(Currency.formatPaise(line.amountPaise), x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[2].1, alignment: .right)
=======
            drawText("", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[2].1)
            x += columns[2].1 + columnGap
            drawText("", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[3].1)
            x += columns[3].1 + columnGap
            drawText(Currency.formatPaise(line.amountPaise), x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[4].1, alignment: .right)
>>>>>>> origin/main
            advance(rowHeight)
        }

        advance(8)
        let bottomPath = NSBezierPath()
        bottomPath.lineWidth = 0.6
        bottomPath.move(to: CGPoint(x: margin, y: cursorY - 4))
        bottomPath.line(to: CGPoint(x: bounds.width - margin, y: cursorY - 4))
        bottomPath.stroke()
        advance(18)

<<<<<<< HEAD
        drawText("Total", x: bounds.width - margin - 180, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 100, alignment: .right)
        drawText(Currency.formatPaise(visibleTotalPaise), x: bounds.width - margin - 80, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 80, alignment: .right)
        advance(28)

        func drawTaxRow(_ label: String, _ paise: Int64) {
            drawText(label, x: bounds.width - margin - 180, y: cursorY - 16, font: .systemFont(ofSize: 10), width: 100, alignment: .right)
            drawText(Currency.formatPaise(paise), x: bounds.width - margin - 80, y: cursorY - 16, font: .systemFont(ofSize: 10), width: 80, alignment: .right)
            advance(18)
        }

        // Only the applicable tax pair is shown (CGST+SGST for intra-state,
        // IGST for inter-state), matching how a real GST invoice never
        // shows both -- never guessed from place-of-supply, always read
        // straight from what was actually posted (AVL-P0-022).
        if taxBreakdown.taxableValuePaise != 0 || taxBreakdown.igstPaise != 0
            || taxBreakdown.cgstPaise != 0 || taxBreakdown.sgstPaise != 0 || taxBreakdown.cessPaise != 0 {
            drawTaxRow("Taxable Value", taxBreakdown.taxableValuePaise)
            if taxBreakdown.igstPaise != 0 {
                drawTaxRow("IGST", taxBreakdown.igstPaise)
            }
            if taxBreakdown.cgstPaise != 0 {
                drawTaxRow("CGST", taxBreakdown.cgstPaise)
            }
            if taxBreakdown.sgstPaise != 0 {
                drawTaxRow("SGST", taxBreakdown.sgstPaise)
            }
            if taxBreakdown.cessPaise != 0 {
                drawTaxRow("CESS", taxBreakdown.cessPaise)
            }
            advance(10)
        }

        if !stockRows.isEmpty {
            advance(8)
            drawText("Stock Detail", x: margin, y: cursorY - 16, font: .boldSystemFont(ofSize: 11))
            advance(20)
            let stockColumns: [(String, CGFloat)] = [
                ("Item", 170), ("HSN", 70), ("Qty", 70), ("Unit", 60), ("Rate", 70), ("Value", 90)
            ]
            var sx = margin
            for (title, width) in stockColumns {
                drawText(title, x: sx, y: cursorY - 16, font: .boldSystemFont(ofSize: 9), width: width)
                sx += width + columnGap
            }
            advance(16)
            for row in stockRows {
                sx = margin
                drawText(row.itemName, x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[0].1)
                sx += stockColumns[0].1 + columnGap
                drawText(row.hsnCode ?? "", x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[1].1)
                sx += stockColumns[1].1 + columnGap
                drawText(row.quantityDisplay, x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[2].1)
                sx += stockColumns[2].1 + columnGap
                drawText(row.unit, x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[3].1)
                sx += stockColumns[3].1 + columnGap
                drawText(row.rateDisplay, x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[4].1, alignment: .right)
                sx += stockColumns[4].1 + columnGap
                drawText(row.valueDisplay, x: sx, y: cursorY - 14, font: .systemFont(ofSize: 9), width: stockColumns[5].1, alignment: .right)
                advance(16)
            }
        }

        // Signed QR / e-invoice IRN is intentionally not implemented here:
        // it requires an online call to the government e-invoice portal for
        // IRN issuance, which conflicts with Avelo's R-1 (100% offline, zero
        // network calls). See Docs/Avelo_Release_Board.md AVL-P0-022 /
        // AVL-P1-008 -- revisit only if R-1 itself is ever revisited.
=======
        let totalPaise = visibleLines.reduce(Int64(0)) { $0 + $1.0.amountPaise }
        drawText("Total", x: bounds.width - margin - 180, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 100, alignment: .right)
        drawText(Currency.formatPaise(totalPaise), x: bounds.width - margin - 80, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 80, alignment: .right)
>>>>>>> origin/main
        drawText("Generated by Avelo", x: margin, y: 22, font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
    }
}
