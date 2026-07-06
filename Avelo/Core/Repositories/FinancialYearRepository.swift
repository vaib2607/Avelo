import Foundation

public struct FinancialYearRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: FinancialYear.ID) throws -> FinancialYear? {
        try db.queryOne(
            "SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at FROM avelo_financial_years WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToFinancialYear($0) }
    }

    public func listForCompany(_ companyId: Company.ID) throws -> [FinancialYear] {
        try db.query(
            "SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at FROM avelo_financial_years WHERE company_id = ? ORDER BY start_date ASC",
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToFinancialYear($0) }
    }

    public func findOpenForCompany(_ companyId: Company.ID) throws -> [FinancialYear] {
        try db.query(
            "SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at FROM avelo_financial_years WHERE company_id = ? AND is_locked = 0 AND COALESCE(is_closed, 0) = 0 ORDER BY start_date ASC",
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToFinancialYear($0) }
    }

    public func findMostRecent(_ companyId: Company.ID) throws -> FinancialYear? {
        try db.queryOne(
            "SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at FROM avelo_financial_years WHERE company_id = ? ORDER BY start_date DESC LIMIT 1",
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToFinancialYear($0) }
    }

    public func overlaps(companyId: Company.ID,
                         startDate: Date,
                         endDate: Date,
                         excluding existingFinancialYearId: FinancialYear.ID? = nil) throws -> [FinancialYear] {
        var sql = """
        SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at
        FROM avelo_financial_years
        WHERE company_id = ?
          AND NOT (? < start_date OR ? > end_date)
        """
        var bind: [SQLValue] = [
            .text(companyId.uuidString),
            .date(endDate),
            .date(startDate)
        ]
        if let existingFinancialYearId {
            sql += " AND id <> ?"
            bind.append(.text(existingFinancialYearId.uuidString))
        }
        sql += " ORDER BY start_date ASC, created_at ASC, id ASC"
        return try db.query(sql, bind: bind) { try Self.rowToFinancialYear($0) }
    }

    public func containing(date: Date,
                           companyId: Company.ID,
                           limit: Int = 2) throws -> [FinancialYear] {
        try db.query(
            """
            SELECT id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at
            FROM avelo_financial_years
            WHERE company_id = ?
              AND ? BETWEEN start_date AND end_date
            ORDER BY start_date DESC, end_date DESC, created_at ASC, id ASC
            LIMIT ?
            """,
            bind: [
                .text(companyId.uuidString),
                .date(date),
                .integer(Int64(limit))
            ]
        ) { try Self.rowToFinancialYear($0) }
    }

    public func insert(_ fy: FinancialYear) throws {
        try db.execute(
            "INSERT INTO avelo_financial_years (id, company_id, label, start_date, end_date, books_begin_date, is_locked, is_closed, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(fy.id.uuidString),
                .text(fy.companyId.uuidString),
                .text(fy.label),
                .date(fy.startDate),
                .date(fy.endDate),
                .date(fy.booksBeginDate),
                .bool(fy.isLocked),
                .bool(fy.isClosed),
                .timestamp(fy.createdAt)
            ]
        )
    }

    public func lock(_ id: FinancialYear.ID) throws {
        try db.execute(
            "UPDATE avelo_financial_years SET is_locked = 1 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    public func unlock(_ id: FinancialYear.ID) throws {
        try db.execute(
            "UPDATE avelo_financial_years SET is_locked = 0 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    public func markClosed(_ id: FinancialYear.ID) throws {
        try db.execute(
            "UPDATE avelo_financial_years SET is_closed = 1, is_locked = 1 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    static func rowToFinancialYear(_ r: Row) throws -> FinancialYear {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_financial_years.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_financial_years.company_id")
        return FinancialYear(
            id: id,
            companyId: companyId,
            label: try r.requiredText("label"),
            startDate: try r.requiredDate("start_date"),
            endDate: try r.requiredDate("end_date"),
            booksBeginDate: try r.requiredDate("books_begin_date"),
            isLocked: try r.requiredBool("is_locked"),
            isClosed: try r.requiredBool("is_closed"),
            createdAt: try r.timestamp("created_at")
        )
    }
}
