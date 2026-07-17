import Foundation

public struct MigrationV024: Migration {
    public let version: SchemaVersion = .v24
    public let description = "Add focused party profiles with explicit customer/supplier usage"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE avelo_party_profiles (
                account_id TEXT NOT NULL PRIMARY KEY REFERENCES avelo_accounts(id) ON DELETE CASCADE,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                usage TEXT NOT NULL CHECK(usage IN ('customer','supplier','both')),
                credit_limit_paise INTEGER CHECK(credit_limit_paise IS NULL OR credit_limit_paise >= 0),
                default_credit_period_days INTEGER CHECK(default_credit_period_days IS NULL OR default_credit_period_days >= 0),
                maintain_billwise INTEGER NOT NULL DEFAULT 0 CHECK(maintain_billwise IN (0,1)),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        try db.execute("CREATE INDEX idx_avelo_party_profiles_company_usage ON avelo_party_profiles(company_id, usage);")
        try db.execute(
            """
            CREATE TRIGGER trg_avelo_party_profiles_company_insert
            BEFORE INSERT ON avelo_party_profiles
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_accounts a
                WHERE a.id = NEW.account_id AND a.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'Party profile account must belong to the same company.');
            END;
            """
        )
        try db.execute(
            """
            CREATE TRIGGER trg_avelo_party_profiles_company_update
            BEFORE UPDATE ON avelo_party_profiles
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_accounts a
                WHERE a.id = NEW.account_id AND a.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'Party profile account must belong to the same company.');
            END;
            """
        )
    }
}
