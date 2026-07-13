import Foundation

public final class GSTService: Sendable {

    public let db: SQLiteDatabase
    public let reportRepository: ReportRepository
    public let voucherRepository: VoucherRepository
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.reportRepository = ReportRepository(db: db)
        self.voucherRepository = VoucherRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public struct GSTReturn: Sendable {
        public let period: String
        public let outwardTaxablePaise: Int64
        public let outwardTaxPaise: Int64
        public let inwardTaxablePaise: Int64
        public let inwardTaxPaise: Int64
        public let igstPaise: Int64
        public let cgstPaise: Int64
        public let sgstPaise: Int64
        public let cessPaise: Int64
    }

    /// Per-voucher CGST/SGST/IGST/CESS split, for invoice PDF rendering
    /// (AVL-P0-022). Unlike `gstr1InvoiceRows`, this never excludes a
    /// voucher for having zero tax (e.g. a purchase from an unregistered
    /// party legitimately has no tax lines) -- the caller decides how to
    /// render an all-zero breakdown, this just reports the truth.
    public struct VoucherTaxBreakdown: Sendable, Hashable {
        public let taxableValuePaise: Int64
        public let igstPaise: Int64
        public let cgstPaise: Int64
        public let sgstPaise: Int64
        public let cessPaise: Int64
    }

    public struct GSTR1InvoiceRow: Sendable, Hashable {
        public let voucherId: Voucher.ID
        public let invoiceNumber: String
        public let invoiceDate: Date
        public let partyName: String
        public let partyGSTIN: String?
        public let taxableValuePaise: Int64
        public let igstPaise: Int64
        public let cgstPaise: Int64
        public let sgstPaise: Int64
        public let cessPaise: Int64
        public let invoiceValuePaise: Int64
    }

    public func summary(fromDate: Date, toDate: Date) throws -> ReportResult.GstSummary {
        try reportRepository.gstSummary(fromDate: fromDate, toDate: toDate,
                                         filter: ReportResult.ReportFilter(companyId: companyId))
    }

    public func buildReturn(fromDate: Date, toDate: Date) throws -> GSTReturn {
        let s = try summary(fromDate: fromDate, toDate: toDate)
        let period = DateFormatters.gstReturn.string(from: fromDate) + " - " + DateFormatters.gstReturn.string(from: toDate)
        return GSTReturn(
            period: period,
            outwardTaxablePaise: s.outputTaxablePaise,
            outwardTaxPaise: s.outputTaxPaise,
            inwardTaxablePaise: s.inputTaxablePaise,
            inwardTaxPaise: s.inputTaxPaise,
            igstPaise: s.igstPaise,
            cgstPaise: s.cgstPaise,
            sgstPaise: s.sgstPaise,
            cessPaise: s.cessPaise
        )
    }

    public func exportGSTSummaryCSV(fromDate: Date, toDate: Date) throws -> Data {
        let s = try summary(fromDate: fromDate, toDate: toDate)
        let rows: [[String]] = [
            ["Period", "Outward Taxable (Rs)", "Outward Tax (Rs)", "Inward Taxable (Rs)", "Inward Tax (Rs)", "IGST (Rs)", "CGST (Rs)", "SGST (Rs)"],
            [
                DateFormatters.gstReturn.string(from: fromDate) + " - " + DateFormatters.gstReturn.string(from: toDate),
                Currency.formatPaise(s.outputTaxablePaise, style: .plain),
                Currency.formatPaise(s.outputTaxPaise, style: .plain),
                Currency.formatPaise(s.inputTaxablePaise, style: .plain),
                Currency.formatPaise(s.inputTaxPaise, style: .plain),
                Currency.formatPaise(s.igstPaise, style: .plain),
                Currency.formatPaise(s.cgstPaise, style: .plain),
                Currency.formatPaise(s.sgstPaise, style: .plain)
            ]
        ]
        var csv = rows.map { $0.joined(separator: ",") }.joined(separator: "\n")
        csv += "\n"
        return Data(csv.utf8)
    }

    public func voucherTaxBreakdown(voucherId: Voucher.ID) throws -> VoucherTaxBreakdown {
        let outputCodes = ["IGST_OUTPUT", "CGST_OUTPUT", "SGST_OUTPUT", "CESS"]
        let codeList = outputCodes.map { "'\($0)'" }.joined(separator: ",")
        let sql = """
            SELECT
                   COALESCE(SUM(CASE
                       WHEN tax.code NOT IN (\(codeList)) AND l.side = 'credit' THEN l.amount_paise
                       ELSE 0 END), 0) AS taxable_value,
                   COALESCE(SUM(CASE WHEN tax.code = 'IGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS igst,
                   COALESCE(SUM(CASE WHEN tax.code = 'CGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS cgst,
                   COALESCE(SUM(CASE WHEN tax.code = 'SGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS sgst,
                   COALESCE(SUM(CASE WHEN tax.code = 'CESS' THEN l.amount_paise ELSE 0 END), 0) AS cess
            FROM avelo_vouchers v
            JOIN avelo_ledger_lines l ON l.voucher_id = v.id AND l.company_id = v.company_id
            JOIN avelo_accounts tax ON tax.id = l.account_id
            WHERE v.company_id = ?
              AND v.id = ?
            GROUP BY v.id
        """
        let row = try db.queryOne(sql, bind: [.text(companyId.uuidString), .text(voucherId.uuidString)]) { row in
            VoucherTaxBreakdown(
                taxableValuePaise: row.int("taxable_value"),
                igstPaise: row.int("igst"),
                cgstPaise: row.int("cgst"),
                sgstPaise: row.int("sgst"),
                cessPaise: row.int("cess")
            )
        }
        return row ?? VoucherTaxBreakdown(taxableValuePaise: 0, igstPaise: 0, cgstPaise: 0, sgstPaise: 0, cessPaise: 0)
    }

    public func gstr1InvoiceRows(fromDate: Date, toDate: Date) throws -> [GSTR1InvoiceRow] {
        let outputCodes = ["IGST_OUTPUT", "CGST_OUTPUT", "SGST_OUTPUT", "CESS"]
        let codeList = outputCodes.map { "'\($0)'" }.joined(separator: ",")
        let sql = """
            SELECT v.id,
                   v.number,
                   v.date,
                   COALESCE(pa.name, '') AS party_name,
                   pa.gstin AS party_gstin,
                   COALESCE(SUM(CASE
                       WHEN tax.code NOT IN (\(codeList)) AND l.side = 'credit' THEN l.amount_paise
                       ELSE 0 END), 0) AS taxable_value,
                   COALESCE(SUM(CASE WHEN tax.code = 'IGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS igst,
                   COALESCE(SUM(CASE WHEN tax.code = 'CGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS cgst,
                   COALESCE(SUM(CASE WHEN tax.code = 'SGST_OUTPUT' THEN l.amount_paise ELSE 0 END), 0) AS sgst,
                   COALESCE(SUM(CASE WHEN tax.code = 'CESS' THEN l.amount_paise ELSE 0 END), 0) AS cess,
                   COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise ELSE 0 END), 0) AS invoice_value
            FROM avelo_vouchers v
            JOIN avelo_ledger_lines l ON l.voucher_id = v.id AND l.company_id = v.company_id
            JOIN avelo_accounts tax ON tax.id = l.account_id
            LEFT JOIN avelo_accounts pa ON pa.id = v.party_account_id
            WHERE v.company_id = ?
              AND v.is_posted = 1
              AND v.date BETWEEN ? AND ?
            GROUP BY v.id, v.number, v.date, pa.name, pa.gstin
            HAVING igst != 0 OR cgst != 0 OR sgst != 0 OR cess != 0
            ORDER BY v.date ASC, v.number ASC
        """
        return try db.query(sql, bind: [.text(companyId.uuidString), .date(fromDate), .date(toDate)]) { row in
            GSTR1InvoiceRow(
                voucherId: try UUIDParsing.required(row.text("id"), field: "gstr1.invoice.voucher_id"),
                invoiceNumber: row.text("number"),
                invoiceDate: row.date("date"),
                partyName: row.text("party_name"),
                partyGSTIN: row.optionalText("party_gstin"),
                taxableValuePaise: row.int("taxable_value"),
                igstPaise: row.int("igst"),
                cgstPaise: row.int("cgst"),
                sgstPaise: row.int("sgst"),
                cessPaise: row.int("cess"),
                invoiceValuePaise: row.int("invoice_value")
            )
        }
    }

    public func exportGSTR1InvoiceCSV(fromDate: Date, toDate: Date) throws -> Data {
        let header = [
            "Invoice Number",
            "Invoice Date",
            "Party Name",
            "Party GSTIN",
            "Taxable Value (Rs)",
            "IGST (Rs)",
            "CGST (Rs)",
            "SGST (Rs)",
            "CESS (Rs)",
            "Invoice Value (Rs)"
        ]
        let rows = try gstr1InvoiceRows(fromDate: fromDate, toDate: toDate).map { row in
            [
                row.invoiceNumber,
                DateFormatters.formatIsoDate(row.invoiceDate),
                row.partyName,
                row.partyGSTIN ?? "",
                Currency.formatPaise(row.taxableValuePaise, style: .plain),
                Currency.formatPaise(row.igstPaise, style: .plain),
                Currency.formatPaise(row.cgstPaise, style: .plain),
                Currency.formatPaise(row.sgstPaise, style: .plain),
                Currency.formatPaise(row.cessPaise, style: .plain),
                Currency.formatPaise(row.invoiceValuePaise, style: .plain)
            ].map(Self.csvField)
        }
        let csv = ([header.map(Self.csvField)] + rows)
            .map { $0.joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    @available(*, deprecated, message: "This export is summary-only; use exportGSTSummaryCSV(fromDate:toDate:) for the honest label.")
    public func exportGSTR1(fromDate: Date, toDate: Date) throws -> Data {
        try exportGSTSummaryCSV(fromDate: fromDate, toDate: toDate)
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        let hardened: String
        if let first = escaped.first, ["=", "+", "-", "@"].contains(first) {
            hardened = "'" + escaped
        } else {
            hardened = escaped
        }
        guard hardened.contains(",") || hardened.contains("\"") || hardened.contains("\n") else { return hardened }
        return "\"\(hardened)\""
    }
}
