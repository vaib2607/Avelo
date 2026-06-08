import Foundation

public final class ReportService: Sendable {

    public let repository: ReportRepository
    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = ReportRepository(db: db)
        self.companyId = companyId
    }

    public func makeFilter(financialYearId: FinancialYear.ID? = nil,
                           fromDate: Date? = nil,
                           toDate: Date? = nil,
                           accountId: Account.ID? = nil,
                           voucherTypeCodes: Set<VoucherType.Code> = []) -> ReportResult.ReportFilter {
        ReportResult.ReportFilter(
            companyId: companyId,
            financialYearId: financialYearId,
            fromDate: fromDate,
            toDate: toDate,
            accountId: accountId,
            voucherTypeCodes: voucherTypeCodes
        )
    }

    public func ledger(accountId: Account.ID,
                       financialYearId: FinancialYear.ID? = nil,
                       fromDate: Date? = nil,
                       toDate: Date? = nil) throws -> ReportResult.LedgerReport {
        let f = makeFilter(financialYearId: financialYearId, fromDate: fromDate, toDate: toDate, accountId: accountId)
        return try repository.ledgerReport(filter: f, accountId: accountId)
    }

    public func trialBalance(asOfDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.TrialBalance {
        let f = makeFilter(financialYearId: financialYearId)
        return try repository.trialBalance(asOfDate: asOfDate, filter: f)
    }

    public func profitAndLoss(fromDate: Date, toDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.ProfitLoss {
        let f = makeFilter(financialYearId: financialYearId)
        return try repository.profitAndLoss(fromDate: fromDate, toDate: toDate, filter: f)
    }

    public func balanceSheet(asOfDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.BalanceSheet {
        let f = makeFilter(financialYearId: financialYearId)
        return try repository.balanceSheet(asOfDate: asOfDate, filter: f)
    }

    public func gstSummary(fromDate: Date, toDate: Date) throws -> ReportResult.GstSummary {
        let f = makeFilter()
        return try repository.gstSummary(fromDate: fromDate, toDate: toDate, filter: f)
    }

    public func dayBook(fromDate: Date, toDate: Date) throws -> [ReportResult.DayBookRow] {
        let f = makeFilter()
        return try repository.dayBook(fromDate: fromDate, toDate: toDate, filter: f)
    }

    public func outstanding(asOfDate: Date, direction: ReportResult.OutstandingReport.Direction) throws -> ReportResult.OutstandingReport {
        let f = makeFilter()
        return try repository.outstanding(asOfDate: asOfDate, direction: direction, filter: f)
    }

    public func stockValuation(asOfDate: Date) throws -> ReportResult.StockValuationReport {
        let f = makeFilter()
        return try repository.stockValuation(asOfDate: asOfDate, filter: f)
    }
}
