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
            FROM avelo_ledger_lines
            WHERE voucher_id = ?
            ORDER BY line_order ASC
            """,
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToLine($0) }
    }

    public func insertBatch(_ lines: [LedgerLine]) throws {
<<<<<<< HEAD:Avelo/Core/Repositories/LedgerLineRepository.swift
        let maximumRowsPerStatement = 99 // 99 rows * 9 columns = 891 bindings
        var start = lines.startIndex
        while start < lines.endIndex {
            let end = lines.index(start, offsetBy: maximumRowsPerStatement, limitedBy: lines.endIndex) ?? lines.endIndex
            let rowPlaceholder = "(" + Array(repeating: "?", count: 9).joined(separator: ", ") + ")"
            let values = Array(repeating: rowPlaceholder, count: lines.distance(from: start, to: end)).joined(separator: ", ")
            var bindings: [SQLValue] = []
            bindings.reserveCapacity(lines.distance(from: start, to: end) * 9)
            for line in lines[start..<end] {
                bindings.append(contentsOf: Self.insertBindings(for: line))
=======
        try db.write { tx in
            for line in lines {
                try tx.execute(
                    """
                    INSERT INTO avelo_ledger_lines
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
>>>>>>> origin/main:Mally/Core/Repositories/LedgerLineRepository.swift
            }
            try db.execute(
                """
                INSERT INTO avelo_ledger_lines
                (id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order)
                VALUES \(values)
                """,
                bindings
            )
            start = end
        }
    }

    private static func insertBindings(for line: LedgerLine) -> [SQLValue] {
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
    }

    public func deleteForVoucher(_ voucherId: Voucher.ID) throws {
        try db.execute(
            "DELETE FROM avelo_ledger_lines WHERE voucher_id = ?",
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
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
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
        let debit = result?.0 ?? 0
        let credit = result?.1 ?? 0
        return Totals(debit: debit, credit: credit)
    }

    static func rowToLine(_ r: Row) throws -> LedgerLine {
<<<<<<< HEAD:Avelo/Core/Repositories/LedgerLineRepository.swift
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_ledger_lines.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_ledger_lines.company_id")
        let voucherId = try UUIDParsing.required(r.requiredText("voucher_id"), field: "avelo_ledger_lines.voucher_id")
        let accountId = try UUIDParsing.required(r.requiredText("account_id"), field: "avelo_ledger_lines.account_id")
        let side: EntrySide = try r.enumValue("side")
=======
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_ledger_lines.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_ledger_lines.company_id")
        let voucherId = try UUIDParsing.required(r.text("voucher_id"), field: "avelo_ledger_lines.voucher_id")
        let accountId = try UUIDParsing.required(r.text("account_id"), field: "avelo_ledger_lines.account_id")
        let sideRaw = r.text("side")
        let side = EntrySide(rawValue: sideRaw) ?? .debit
>>>>>>> origin/main:Mally/Core/Repositories/LedgerLineRepository.swift
        return LedgerLine(
            id: id,
            companyId: companyId,
            voucherId: voucherId,
            accountId: accountId,
            amountPaise: try r.requiredInt("amount_paise"),
            side: side,
            taxCode: try r.checkedOptionalText("tax_code"),
            costCenter: try r.checkedOptionalText("cost_center"),
            lineOrder: Int(try r.requiredInt("line_order"))
        )
    }
}
