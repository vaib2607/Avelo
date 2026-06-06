import Foundation

public struct LedgerLineRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findForVoucher(_ voucherId: Voucher.ID) throws -> [LedgerLine] {
        try db.query(
            """
            SELECT id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order
            FROM mally_ledger_lines
            WHERE voucher_id = ?
            ORDER BY line_order ASC
            """,
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToLine($0) }
    }

    public func insertBatch(_ lines: [LedgerLine]) throws {
        try db.write { tx in
            for line in lines {
                try tx.execute(
                    """
                    INSERT INTO mally_ledger_lines
                    (id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(line.id.uuidString),
                        .text(line.companyId.uuidString),
                        .text(line.voucherId.uuidString),
                        .text(line.accountId.uuidString),
                        .integer(line.amountPaise),
                        .text(line.side.rawValue),
                        .optionalText(line.taxCode),
                        .optionalText(line.costCenter),
                        .integer(Int64(line.lineOrder))
                    ]
                )
            }
        }
    }

    public func deleteForVoucher(_ voucherId: Voucher.ID) throws {
        try db.execute(
            "DELETE FROM mally_ledger_lines WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
    }

    public struct AggregationFilter: Sendable {
        public var companyId: Company.ID
        public var accountId: Account.ID
        public var fromDate: Date?
        public var toDate: Date?
        public var includeVouchersByReversalFlag: Bool

        public init(companyId: Company.ID,
                    accountId: Account.ID,
                    fromDate: Date? = nil,
                    toDate: Date? = nil,
                    includeVouchersByReversalFlag: Bool = false) {
            self.companyId = companyId
            self.accountId = accountId
            self.fromDate = fromDate
            self.toDate = toDate
            self.includeVouchersByReversalFlag = includeVouchersByReversalFlag
        }
    }

    public struct Totals: Sendable {
        public let debitPaise: Int64
        public let creditPaise: Int64
        public init(debit: Int64, credit: Int64) {
            self.debitPaise = debit
            self.creditPaise = credit
        }
    }

    public func aggregate(filter: AggregationFilter) throws -> Totals {
        var sql = """
            SELECT
                COALESCE(SUM(CASE WHEN l.side = 'debit'  THEN l.amount_paise ELSE 0 END), 0) AS dr,
                COALESCE(SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM mally_ledger_lines l
            JOIN mally_vouchers v ON v.id = l.voucher_id
            WHERE l.company_id = ? AND l.account_id = ?
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString), .text(filter.accountId.uuidString)]
        if let from = filter.fromDate {
            sql += " AND v.date >= ?"
            bind.append(.date(from))
        }
        if let to = filter.toDate {
            sql += " AND v.date <= ?"
            bind.append(.date(to))
        }
        let result: (Int64, Int64)? = try db.queryOne(sql, bind: bind) { r in
            (r.int("dr"), r.int("cr"))
        }
        return Totals(debit: result?.0 ?? 0, credit: result?.1 ?? 0)
    }

    static func rowToLine(_ r: Row) throws -> LedgerLine {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let voucherId = UUID(uuidString: r.text("voucher_id")) ?? UUID()
        let accountId = UUID(uuidString: r.text("account_id")) ?? UUID()
        let sideRaw = r.text("side")
        let side = EntrySide(rawValue: sideRaw) ?? .debit
        return LedgerLine(
            id: id,
            companyId: companyId,
            voucherId: voucherId,
            accountId: accountId,
            amountPaise: r.int("amount_paise"),
            side: side,
            taxCode: r.optionalText("tax_code"),
            costCenter: r.optionalText("cost_center"),
            lineOrder: Int(r.int("line_order"))
        )
    }
}
