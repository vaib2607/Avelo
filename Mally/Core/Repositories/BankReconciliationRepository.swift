import Foundation

public struct BankReconciliationRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public struct Entry: Sendable {
        public let id: UUID
        public let companyId: Company.ID
        public let bankAccountId: Account.ID
        public let voucherId: Voucher.ID
        public let statementDate: Date
        public let statementAmountPaise: Int64
        public let isCleared: Bool
        public let clearedAt: Date?
        public let note: String?
    }

    public struct StatementLine: Sendable, Identifiable, Hashable, Codable {
        public let id: UUID
        public let accountId: Account.ID
        public let date: Date
        public let amountPaise: Int64
        public let narration: String
        public let isCleared: Bool
    }

    public typealias StatementEntry = StatementLine

    public struct VoucherCandidate: Sendable, Identifiable, Hashable {
        public let id: Voucher.ID
        public let number: String
        public let date: Date
        public let amountPaise: Int64
    }

    public func upsert(_ entry: Entry) throws {
        try db.execute(
            """
            INSERT INTO mally_bank_reconciliations
            (id, company_id, bank_account_id, voucher_id, statement_date,
             statement_amount_paise, is_cleared, cleared_at, note, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(voucher_id) DO UPDATE SET
                statement_date = excluded.statement_date,
                statement_amount_paise = excluded.statement_amount_paise,
                is_cleared = excluded.is_cleared,
                cleared_at = excluded.cleared_at,
                note = excluded.note
            """,
            [
                .text(entry.id.uuidString),
                .text(entry.companyId.uuidString),
                .text(entry.bankAccountId.uuidString),
                .text(entry.voucherId.uuidString),
                .date(entry.statementDate),
                .integer(entry.statementAmountPaise),
                .bool(entry.isCleared),
                .optionalTimestamp(entry.clearedAt),
                .optionalText(entry.note),
                .timestamp(Date())
            ]
        )
    }

    public func list(bankAccountId: Account.ID) throws -> [Entry] {
        try db.query(
            """
            SELECT id, company_id, bank_account_id, voucher_id, statement_date,
                   statement_amount_paise, is_cleared, cleared_at, note
            FROM mally_bank_reconciliations
            WHERE bank_account_id = ?
            """,
            bind: [.text(bankAccountId.uuidString)]
        ) { r in
            Entry(
                id: UUID(uuidString: r.text("id")) ?? UUID(),
                companyId: UUID(uuidString: r.text("company_id")) ?? UUID(),
                bankAccountId: UUID(uuidString: r.text("bank_account_id")) ?? UUID(),
                voucherId: UUID(uuidString: r.text("voucher_id")) ?? UUID(),
                statementDate: r.date("statement_date"),
                statementAmountPaise: r.int("statement_amount_paise"),
                isCleared: r.bool("is_cleared"),
                clearedAt: r.optionalText("cleared_at").flatMap { DateFormatters.parseTimestamp($0) },
                note: r.optionalText("note")
            )
        }
    }

    public func insertStatementLine(accountId: Account.ID,
                                    date: Date,
                                    amountPaise: Int64,
                                    narration: String) throws {
        try db.execute(
            """
            INSERT INTO mally_bank_statement_lines
            (id, account_id, date, amount_paise, narration, is_cleared, created_at)
            VALUES (?, ?, ?, ?, ?, 0, ?)
            """,
            [
                .text(UUID().uuidString),
                .text(accountId.uuidString),
                .date(date),
                .integer(amountPaise),
                .text(narration),
                .timestamp(Date())
            ]
        )
    }

    public func statementLines(accountId: Account.ID, asOf: Date) throws -> [StatementLine] {
        try db.query(
            """
            SELECT id, account_id, date, amount_paise, narration, is_cleared
            FROM mally_bank_statement_lines
            WHERE account_id = ? AND date <= ?
            ORDER BY date ASC, created_at ASC
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in
            StatementLine(
                id: UUID(uuidString: r.text("id")) ?? UUID(),
                accountId: UUID(uuidString: r.text("account_id")) ?? UUID(),
                date: r.date("date"),
                amountPaise: r.int("amount_paise"),
                narration: r.text("narration"),
                isCleared: r.bool("is_cleared")
            )
        }
    }

    public func candidateVouchers(accountId: Account.ID, asOf: Date) throws -> [VoucherCandidate] {
        try db.query(
            """
            SELECT v.id, v.number, v.date, v.total_paise
            FROM mally_vouchers v
            JOIN mally_ledger_lines l ON l.voucher_id = v.id
            WHERE l.account_id = ? AND v.date <= ?
            GROUP BY v.id
            ORDER BY v.date ASC
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in
            VoucherCandidate(
                id: UUID(uuidString: r.text("id")) ?? UUID(),
                number: r.text("number"),
                date: r.date("date"),
                amountPaise: r.int("total_paise")
            )
        }
    }

    public func bookBalance(accountId: Account.ID, asOf: Date) throws -> Int64 {
        let row: Int64? = try db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise
                                     WHEN l.side = 'credit' THEN -l.amount_paise
                                     ELSE 0 END), 0) AS bal
            FROM mally_ledger_lines l
            JOIN mally_vouchers v ON v.id = l.voucher_id
            WHERE l.account_id = ? AND v.date <= ?
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in r.int(0) }
        return row ?? 0
    }

    public func clearStatementLine(id: UUID) throws {
        try db.execute(
            "UPDATE mally_bank_statement_lines SET is_cleared = 1 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }
}
