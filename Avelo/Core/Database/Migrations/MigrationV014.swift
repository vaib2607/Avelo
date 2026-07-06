import Foundation

public struct MigrationV014: Migration {
    public let version: SchemaVersion = .v14
    public let description: String = "Add per-financial-year carried opening balances."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_financial_year_opening_balances (
                financial_year_id TEXT NOT NULL REFERENCES avelo_financial_years(id) ON DELETE CASCADE,
                source_financial_year_id TEXT NOT NULL REFERENCES avelo_financial_years(id) ON DELETE CASCADE,
                account_id TEXT NOT NULL REFERENCES avelo_accounts(id) ON DELETE CASCADE,
                opening_balance_paise INTEGER NOT NULL,
                opening_balance_side TEXT NOT NULL CHECK(opening_balance_side IN ('debit','credit')),
                created_at TEXT NOT NULL,
                PRIMARY KEY (financial_year_id, account_id)
            );
            """
        )
        try db.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_avelo_fy_opening_balances_source
            ON avelo_financial_year_opening_balances(source_financial_year_id);
            """
        )
    }
}
