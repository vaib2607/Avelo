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
}
