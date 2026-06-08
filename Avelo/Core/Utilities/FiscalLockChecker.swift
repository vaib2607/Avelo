import Foundation

public struct FiscalLockChecker: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func isLocked(financialYearId: FinancialYear.ID) throws -> Bool {
        let v: Int64? = try db.queryOne(
            "SELECT is_locked FROM avelo_financial_years WHERE id = ?",
            bind: [.text(financialYearId.uuidString)]
        ) { r in r.int("is_locked") }
        return (v ?? 0) != 0
    }

    public func isClosed(financialYearId: FinancialYear.ID) throws -> Bool {
        let v: Int64? = try db.queryOne(
            "SELECT is_closed FROM avelo_financial_years WHERE id = ?",
            bind: [.text(financialYearId.uuidString)]
        ) { r in r.int("is_closed") }
        return (v ?? 0) != 0
    }

    public func financialYear(containing date: Date,
                              companyId: Company.ID) throws -> FinancialYear.ID? {
        let dateStr = DateFormatters.formatIsoDate(date)
        let id: String? = try db.queryOne(
            "SELECT id FROM avelo_financial_years WHERE company_id = ? AND ? BETWEEN start_date AND end_date LIMIT 1",
            bind: [.text(companyId.uuidString), .text(dateStr)]
        ) { r in r.text("id") }
        return id.flatMap { UUID(uuidString: $0) }
    }

    public func assertOpen(financialYearId: FinancialYear.ID) throws {
        if try isLocked(financialYearId: financialYearId) {
            throw AppError.businessRule("Financial year is locked")
        }
    }
}
