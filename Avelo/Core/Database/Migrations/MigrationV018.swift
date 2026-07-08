import Foundation

public struct MigrationV018: Migration {
    public let version: SchemaVersion = .v18
    public let description = "Add voucher entry draft autosave table"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_voucher_drafts (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE CASCADE,
                voucher_type_code TEXT NOT NULL,
                date TEXT NOT NULL,
                party_account_id TEXT,
                narration TEXT NOT NULL DEFAULT '',
                bill_reference_type TEXT,
                bill_reference_number TEXT,
                cheque_number TEXT,
                cheque_due_date TEXT,
                lines_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_voucher_drafts_company ON avelo_voucher_drafts(company_id, updated_at);")
    }
}
