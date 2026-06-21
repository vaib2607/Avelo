import Foundation

public struct MigrationV004: Migration {
    public let version: SchemaVersion = .v4
    public let description: String = "Add raw imported bank statement lines for reconciliation."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS avelo_bank_statement_lines (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES avelo_companies(id),
            bank_account_id TEXT NOT NULL REFERENCES avelo_accounts(id),
            statement_date TEXT NOT NULL,
            amount_paise INTEGER NOT NULL,
            narration TEXT NOT NULL,
            import_batch_id TEXT,
            imported_at TEXT NOT NULL,
            matched_voucher_id TEXT REFERENCES avelo_vouchers(id),
            is_cleared INTEGER NOT NULL DEFAULT 0 CHECK(is_cleared IN (0, 1)),
            cleared_at TEXT
        );
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bank_statement_lines_account_date ON avelo_bank_statement_lines(bank_account_id, statement_date);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bank_statement_lines_clearance ON avelo_bank_statement_lines(company_id, is_cleared, statement_date);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bank_statement_lines_matched_voucher ON avelo_bank_statement_lines(matched_voucher_id);")
    }
}
