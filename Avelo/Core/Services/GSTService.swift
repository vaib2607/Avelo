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
            cessPaise: 0
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

    @available(*, deprecated, message: "This export is summary-only; use exportGSTSummaryCSV(fromDate:toDate:) for the honest label.")
    public func exportGSTR1(fromDate: Date, toDate: Date) throws -> Data {
        try exportGSTSummaryCSV(fromDate: fromDate, toDate: toDate)
    }
}
