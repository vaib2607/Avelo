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
<<<<<<< HEAD
        public let companyId: Company.ID
=======
>>>>>>> origin/main
        public let accountId: Account.ID
        public let date: Date
        public let amountPaise: Int64
        public let narration: String
<<<<<<< HEAD
        public let matchedVoucherId: Voucher.ID?
        public let isCleared: Bool

        public init(id: UUID,
                    companyId: Company.ID,
                    accountId: Account.ID,
                    date: Date,
                    amountPaise: Int64,
                    narration: String,
                    matchedVoucherId: Voucher.ID? = nil,
                    isCleared: Bool) {
            self.id = id
            self.companyId = companyId
            self.accountId = accountId
            self.date = date
            self.amountPaise = amountPaise
            self.narration = narration
            self.matchedVoucherId = matchedVoucherId
            self.isCleared = isCleared
        }
=======
        public let isCleared: Bool
>>>>>>> origin/main
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
            INSERT INTO avelo_bank_reconciliations
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
            FROM avelo_bank_reconciliations
            WHERE bank_account_id = ?
            """,
            bind: [.text(bankAccountId.uuidString)]
        ) { r in
            Entry(
<<<<<<< HEAD
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_bank_reconciliations.id"),
                companyId: try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_bank_reconciliations.company_id"),
                bankAccountId: try UUIDParsing.required(r.requiredText("bank_account_id"), field: "avelo_bank_reconciliations.bank_account_id"),
                voucherId: try UUIDParsing.required(r.requiredText("voucher_id"), field: "avelo_bank_reconciliations.voucher_id"),
                statementDate: try r.requiredDate("statement_date"),
                statementAmountPaise: try r.requiredInt("statement_amount_paise"),
                isCleared: try r.requiredBool("is_cleared"),
                clearedAt: try r.optionalTimestamp("cleared_at"),
                note: try r.checkedOptionalText("note")
=======
                id: try UUIDParsing.required(r.text("id"), field: "avelo_bank_reconciliations.id"),
                companyId: try UUIDParsing.required(r.text("company_id"), field: "avelo_bank_reconciliations.company_id"),
                bankAccountId: try UUIDParsing.required(r.text("bank_account_id"), field: "avelo_bank_reconciliations.bank_account_id"),
                voucherId: try UUIDParsing.required(r.text("voucher_id"), field: "avelo_bank_reconciliations.voucher_id"),
                statementDate: r.date("statement_date"),
                statementAmountPaise: r.int("statement_amount_paise"),
                isCleared: r.bool("is_cleared"),
                clearedAt: r.optionalText("cleared_at").flatMap { DateFormatters.parseTimestamp($0) },
                note: r.optionalText("note")
>>>>>>> origin/main
            )
        }
    }

<<<<<<< HEAD
    public func insertStatementLine(companyId: Company.ID,
                                    accountId: Account.ID,
                                    date: Date,
                                    amountPaise: Int64,
                                    narration: String,
                                    importBatchId: UUID? = nil) throws {
        try db.execute(
            """
            INSERT INTO avelo_bank_statement_lines
            (id, company_id, bank_account_id, statement_date, amount_paise,
             narration, import_batch_id, imported_at, matched_voucher_id, is_cleared, cleared_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, 0, NULL)
            """,
            [
                .text(UUID().uuidString),
                .text(companyId.uuidString),
=======
    public func insertStatementLine(accountId: Account.ID,
                                    date: Date,
                                    amountPaise: Int64,
                                    narration: String) throws {
        try db.execute(
            """
            INSERT INTO avelo_bank_statement_lines
            (id, account_id, date, amount_paise, narration, is_cleared, created_at)
            VALUES (?, ?, ?, ?, ?, 0, ?)
            """,
            [
                .text(UUID().uuidString),
>>>>>>> origin/main
                .text(accountId.uuidString),
                .date(date),
                .integer(amountPaise),
                .text(narration),
<<<<<<< HEAD
                .optionalText(importBatchId?.uuidString),
=======
>>>>>>> origin/main
                .timestamp(Date())
            ]
        )
    }

    public func statementLines(accountId: Account.ID, asOf: Date) throws -> [StatementLine] {
        try db.query(
            """
<<<<<<< HEAD
            SELECT id, company_id, bank_account_id, statement_date, amount_paise,
                   narration, matched_voucher_id, is_cleared
            FROM avelo_bank_statement_lines
            WHERE bank_account_id = ? AND statement_date <= ?
            ORDER BY statement_date ASC, imported_at ASC, id ASC
=======
            SELECT id, account_id, date, amount_paise, narration, is_cleared
            FROM avelo_bank_statement_lines
            WHERE account_id = ? AND date <= ?
            ORDER BY date ASC, created_at ASC
>>>>>>> origin/main
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in
            StatementLine(
<<<<<<< HEAD
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_bank_statement_lines.id"),
                companyId: try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_bank_statement_lines.company_id"),
                accountId: try UUIDParsing.required(r.requiredText("bank_account_id"), field: "avelo_bank_statement_lines.bank_account_id"),
                date: try r.requiredDate("statement_date"),
                amountPaise: try r.requiredInt("amount_paise"),
                narration: try r.requiredText("narration"),
                matchedVoucherId: try r.checkedOptionalText("matched_voucher_id").map {
                    try UUIDParsing.required($0, field: "avelo_bank_statement_lines.matched_voucher_id")
                },
                isCleared: try r.requiredBool("is_cleared")
            )
        }
    }

    public func findStatementLine(id: UUID) throws -> StatementLine? {
        try db.queryOne(
            """
            SELECT id, company_id, bank_account_id, statement_date, amount_paise,
                   narration, matched_voucher_id, is_cleared
            FROM avelo_bank_statement_lines
            WHERE id = ?
            """,
            bind: [.text(id.uuidString)]
        ) { row in
            StatementLine(
                id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_bank_statement_lines.id"),
                companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_bank_statement_lines.company_id"),
                accountId: try UUIDParsing.required(row.requiredText("bank_account_id"), field: "avelo_bank_statement_lines.bank_account_id"),
                date: try row.requiredDate("statement_date"),
                amountPaise: try row.requiredInt("amount_paise"),
                narration: try row.requiredText("narration"),
                matchedVoucherId: try row.checkedOptionalText("matched_voucher_id").map {
                    try UUIDParsing.required($0, field: "avelo_bank_statement_lines.matched_voucher_id")
                },
                isCleared: try row.requiredBool("is_cleared")
=======
                id: try UUIDParsing.required(r.text("id"), field: "avelo_bank_statement_lines.id"),
                accountId: try UUIDParsing.required(r.text("account_id"), field: "avelo_bank_statement_lines.account_id"),
                date: r.date("date"),
                amountPaise: r.int("amount_paise"),
                narration: r.text("narration"),
                isCleared: r.bool("is_cleared")
>>>>>>> origin/main
            )
        }
    }

    public func candidateVouchers(accountId: Account.ID, asOf: Date) throws -> [VoucherCandidate] {
        try db.query(
            """
            SELECT v.id, v.number, v.date, v.total_paise
            FROM avelo_vouchers v
            JOIN avelo_ledger_lines l ON l.voucher_id = v.id
            WHERE l.account_id = ? AND v.date <= ?
            GROUP BY v.id
            ORDER BY v.date ASC
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in
            VoucherCandidate(
<<<<<<< HEAD
                id: try UUIDParsing.required(r.requiredText("id"), field: "banking.candidate_vouchers.id"),
                number: try r.requiredText("number"),
                date: try r.requiredDate("date"),
                amountPaise: try r.requiredInt("total_paise")
=======
                id: try UUIDParsing.required(r.text("id"), field: "banking.candidate_vouchers.id"),
                number: r.text("number"),
                date: r.date("date"),
                amountPaise: r.int("total_paise")
>>>>>>> origin/main
            )
        }
    }

    public func bookBalance(accountId: Account.ID, asOf: Date) throws -> Int64 {
        let row: Int64? = try db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise
                                     WHEN l.side = 'credit' THEN -l.amount_paise
                                     ELSE 0 END), 0) AS bal
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE l.account_id = ? AND v.date <= ?
            """,
            bind: [.text(accountId.uuidString), .date(asOf)]
        ) { r in r.int(0) }
<<<<<<< HEAD
        let balance = row ?? 0
        assert(balance <= Int64.max / 2)
        return balance
=======
        return row ?? 0
>>>>>>> origin/main
    }

    public func clearStatementLine(id: UUID) throws {
        try db.execute(
<<<<<<< HEAD
            """
            UPDATE avelo_bank_statement_lines
            SET is_cleared = 1, cleared_at = ?
            WHERE id = ?
            """,
            [.timestamp(Date()), .text(id.uuidString)]
=======
            "UPDATE avelo_bank_statement_lines SET is_cleared = 1 WHERE id = ?",
            [.text(id.uuidString)]
>>>>>>> origin/main
        )
    }
}
