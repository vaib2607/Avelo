import Foundation

public final class ReportService: Sendable {

    public let repository: ReportRepository
    public let db: SQLiteDatabase
    public let companyId: Company.ID
    private static let cache = ReportCache()

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
        let key = ReportCache.Key(companyId: companyId, reportType: "ledger", financialYearId: financialYearId, fromDate: fromDate, toDate: toDate, accountId: accountId)
        if let cached: ReportResult.LedgerReport = try Self.cache.value(for: key, db: db) { return cached }
        let report = try repository.ledgerReport(filter: f, accountId: accountId)
        try ReconciliationCheck.verifyLedger(report, db: db, companyId: companyId, accountId: accountId, fromDate: fromDate, toDate: toDate)
        try Self.cache.store(report, for: key, db: db)
        return report
    }

    public func trialBalance(asOfDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.TrialBalance {
        let f = makeFilter(financialYearId: financialYearId)
        let key = ReportCache.Key(companyId: companyId, reportType: "trial_balance", financialYearId: financialYearId, toDate: asOfDate)
        if let cached: ReportResult.TrialBalance = try Self.cache.value(for: key, db: db) { return cached }
        let report = try repository.trialBalance(asOfDate: asOfDate, filter: f)
        try ReconciliationCheck.verifyTrialBalance(report)
        try ReconciliationCheck.verifyPostedVouchersBalance(db: db, companyId: companyId, toDate: asOfDate)
        try Self.cache.store(report, for: key, db: db)
        return report
    }

    public func profitAndLoss(fromDate: Date, toDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.ProfitLoss {
        let f = makeFilter(financialYearId: financialYearId)
        let key = ReportCache.Key(companyId: companyId, reportType: "profit_loss", financialYearId: financialYearId, fromDate: fromDate, toDate: toDate)
        if let cached: ReportResult.ProfitLoss = try Self.cache.value(for: key, db: db) { return cached }
        let report = try repository.profitAndLoss(fromDate: fromDate, toDate: toDate, filter: f)
        try ReconciliationCheck.verifyPostedVouchersBalance(db: db, companyId: companyId, fromDate: fromDate, toDate: toDate)
        try Self.cache.store(report, for: key, db: db)
        return report
    }

    public func balanceSheet(asOfDate: Date, financialYearId: FinancialYear.ID? = nil) throws -> ReportResult.BalanceSheet {
        let f = makeFilter(financialYearId: financialYearId)
        let key = ReportCache.Key(companyId: companyId, reportType: "balance_sheet", financialYearId: financialYearId, toDate: asOfDate)
        if let cached: ReportResult.BalanceSheet = try Self.cache.value(for: key, db: db) { return cached }
        let report = try repository.balanceSheet(asOfDate: asOfDate, filter: f)
        try ReconciliationCheck.verifyPostedVouchersBalance(db: db, companyId: companyId, toDate: asOfDate)
        try Self.cache.store(report, for: key, db: db)
        return report
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

    public static func invalidateCache(companyId: Company.ID) {
        cache.invalidate(companyId: companyId)
    }
}

private final class ReportCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let companyId: Company.ID
        let reportType: String
        var financialYearId: FinancialYear.ID?
        var fromDate: Date?
        var toDate: Date?
        var accountId: Account.ID?
    }

    private struct Entry {
        let voucherCount: Int64
        let value: Any
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    func value<T>(for key: Key, db: SQLiteDatabase) throws -> T? {
        let count = try voucherCount(db: db, companyId: key.companyId)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.voucherCount == count else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value as? T
    }

    func store<T>(_ value: T, for key: Key, db: SQLiteDatabase) throws {
        let count = try voucherCount(db: db, companyId: key.companyId)
        lock.lock()
        entries[key] = Entry(voucherCount: count, value: value)
        lock.unlock()
    }

    func invalidate(companyId: Company.ID) {
        lock.lock()
        entries = entries.filter { $0.key.companyId != companyId }
        lock.unlock()
    }

    private func voucherCount(db: SQLiteDatabase, companyId: Company.ID) throws -> Int64 {
        try db.queryOne(
            "SELECT COUNT(*) AS c FROM avelo_vouchers WHERE company_id = ? AND is_posted = 1",
            bind: [.text(companyId.uuidString)]
        ) { $0.int("c") } ?? 0
    }
}

public enum ReconciliationCheck {
    public static func verifyTrialBalance(_ report: ReportResult.TrialBalance) throws {
        guard report.totalDebitPaise == report.totalCreditPaise else {
            throw AppError.database(.schemaMismatch("Trial Balance does not reconcile to paise."))
        }
    }

    public static func verifyLedger(_ report: ReportResult.LedgerReport,
                                    db: SQLiteDatabase,
                                    companyId: Company.ID,
                                    accountId: Account.ID,
                                    fromDate: Date?,
                                    toDate: Date?) throws {
        let totals = try LedgerLineRepository(db: db).aggregate(
            filter: .init(companyId: companyId, accountId: accountId, fromDate: fromDate, toDate: toDate)
        )
        let rowDebits = report.rows.reduce(Int64(0)) { $0 + $1.debitPaise }
        let rowCredits = report.rows.reduce(Int64(0)) { $0 + $1.creditPaise }
        guard totals.debitPaise == rowDebits,
              totals.creditPaise == rowCredits else {
            throw AppError.database(.schemaMismatch("Ledger report does not reconcile to paise."))
        }
    }

    public static func verifyPostedVouchersBalance(db: SQLiteDatabase,
                                                   companyId: Company.ID,
                                                   fromDate: Date? = nil,
                                                   toDate: Date? = nil) throws {
        var sql = """
            SELECT
              COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
              COALESCE(SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE l.company_id = ? AND v.company_id = ? AND v.is_posted = 1
        """
        var bind: [SQLValue] = [.text(companyId.uuidString), .text(companyId.uuidString)]
        if let fromDate {
            sql += " AND v.date >= ?"
            bind.append(.date(fromDate))
        }
        if let toDate {
            sql += " AND v.date <= ?"
            bind.append(.date(toDate))
        }
        let row = try db.queryOne(sql, bind: bind) { ($0.int("dr"), $0.int("cr")) }
        guard row?.0 == row?.1 else {
            throw AppError.database(.schemaMismatch("Posted vouchers do not reconcile to paise."))
        }
    }
}
