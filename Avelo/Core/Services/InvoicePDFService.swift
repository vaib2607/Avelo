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

        let view = TaxInvoicePDFView(
            frame: NSRect(x: 0, y: 0, width: 595.2, height: 841.8),
            company: company,
            voucher: voucher,
            party: party,
            lines: lines,
            accountById: accountById
        )
        return view.dataWithPDF(inside: view.bounds)
    }
}

private final class TaxInvoicePDFView: NSView {

    private let company: Company
    private let voucher: Voucher
    private let party: Account?
    private let lines: [LedgerLine]
    private let accountById: [Account.ID: Account]

    init(frame frameRect: NSRect,
         company: Company,
         voucher: Voucher,
         party: Account?,
         lines: [LedgerLine],
         accountById: [Account.ID: Account]) {
        self.company = company
        self.voucher = voucher
        self.party = party
        self.lines = lines
        self.accountById = accountById
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { false }

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
            }
        }
        advance(24)
        if !voucher.narration.isEmpty {
            drawText("Narration: \(voucher.narration)", x: margin, y: cursorY - 18, font: .systemFont(ofSize: 11), width: pageWidth)
            advance(20)
        }

        let columns: [(String, CGFloat)] = [
            ("Description", 220),
            ("HSN/SAC", 80),
            ("Qty", 50),
            ("Rate", 80),
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

        let visibleLines = lines.compactMap { line -> (LedgerLine, Account)? in
            if let partyId = voucher.partyAccountId, line.accountId == partyId {
                return nil
            }
            guard let account = accountById[line.accountId] else { return nil }
            return (line, account)
        }

        for (line, account) in visibleLines {
            let rowHeight: CGFloat = 22
            x = margin
            drawText(account.name, x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[0].1)
            x += columns[0].1 + columnGap
            drawText(line.taxCode ?? "", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[1].1)
            x += columns[1].1 + columnGap
            drawText("", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[2].1)
            x += columns[2].1 + columnGap
            drawText("", x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[3].1)
            x += columns[3].1 + columnGap
            drawText(Currency.formatPaise(line.amountPaise), x: x, y: cursorY - 16, font: .systemFont(ofSize: 10), width: columns[4].1, alignment: .right)
            advance(rowHeight)
        }

        advance(8)
        let bottomPath = NSBezierPath()
        bottomPath.lineWidth = 0.6
        bottomPath.move(to: CGPoint(x: margin, y: cursorY - 4))
        bottomPath.line(to: CGPoint(x: bounds.width - margin, y: cursorY - 4))
        bottomPath.stroke()
        advance(18)

        let totalPaise = visibleLines.reduce(Int64(0)) { $0 + $1.0.amountPaise }
        drawText("Total", x: bounds.width - margin - 180, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 100, alignment: .right)
        drawText(Currency.formatPaise(totalPaise), x: bounds.width - margin - 80, y: cursorY - 18, font: .boldSystemFont(ofSize: 11), width: 80, alignment: .right)
        drawText("Generated by Avelo", x: margin, y: 22, font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
    }
}
