import Foundation

public struct MigrationV015: Migration {
    public let version: SchemaVersion = .v15
    public let description = "Add persisted bill allocation workflow rows"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_bill_allocations (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                voucher_id TEXT NOT NULL REFERENCES avelo_vouchers(id) ON DELETE RESTRICT,
                party_account_id TEXT NOT NULL REFERENCES avelo_accounts(id) ON DELETE RESTRICT,
                kind TEXT NOT NULL CHECK(kind IN ('New Ref','Agst Ref','Advance','On Account')),
                reference_number TEXT,
                allocated_paise INTEGER NOT NULL CHECK(allocated_paise > 0),
                created_at TEXT NOT NULL
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bill_allocations_voucher ON avelo_bill_allocations(voucher_id);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bill_allocations_party_ref ON avelo_bill_allocations(company_id, party_account_id, reference_number, created_at);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bill_allocations_party_kind ON avelo_bill_allocations(company_id, party_account_id, kind, created_at);")

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_bill_allocations_company_insert
            BEFORE INSERT ON avelo_bill_allocations
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_vouchers v
                WHERE v.id = NEW.voucher_id AND v.company_id = NEW.company_id
            ) OR NOT EXISTS (
                SELECT 1 FROM avelo_accounts a
                WHERE a.id = NEW.party_account_id AND a.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'Bill allocation references must belong to the same company.');
            END;
            """
        )

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_bill_allocations_company_update
            BEFORE UPDATE ON avelo_bill_allocations
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_vouchers v
                WHERE v.id = NEW.voucher_id AND v.company_id = NEW.company_id
            ) OR NOT EXISTS (
                SELECT 1 FROM avelo_accounts a
                WHERE a.id = NEW.party_account_id AND a.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'Bill allocation references must belong to the same company.');
            END;
            """
        )
    }
}
