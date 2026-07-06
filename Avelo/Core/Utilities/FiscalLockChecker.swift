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
        let matches = try FinancialYearRepository(db: db).containing(date: date, companyId: companyId, limit: 2)
        if matches.count > 1 {
            let labels = matches.map(\.label).joined(separator: ", ")
            throw AppError.businessRule("Overlapping financial years make date lookup ambiguous: \(labels)")
        }
        return matches.first?.id
    }

    public func assertDateOpen(_ date: Date,
                               companyId: Company.ID,
                               mutationLabel: String = "Transaction date") throws -> FinancialYear.ID {
        guard let financialYearId = try financialYear(containing: date, companyId: companyId) else {
            throw AppError.businessRule("\(mutationLabel) is not within any financial year.")
        }
        if try isLocked(financialYearId: financialYearId) {
            throw AppError.businessRule("Financial year is locked")
        }
        return financialYearId
    }

    public func hasAnyLockedYear(companyId: Company.ID) throws -> Bool {
        let count: Int64? = try db.queryOne(
            "SELECT COUNT(*) FROM avelo_financial_years WHERE company_id = ? AND is_locked = 1",
            bind: [.text(companyId.uuidString)]
        ) { $0.int(0) }
        return (count ?? 0) > 0
    }

    public func assertOpen(financialYearId: FinancialYear.ID) throws {
        if try isLocked(financialYearId: financialYearId) {
            throw AppError.businessRule("Financial year is locked")
        }
    }
}
