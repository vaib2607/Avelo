import Foundation

public struct MigrationV016: Migration {
    public let version: SchemaVersion = .v16
    public let description = "Add persisted cheque workflow state for bounce and re-presentation"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_cheques (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                voucher_id TEXT NOT NULL UNIQUE REFERENCES avelo_vouchers(id) ON DELETE RESTRICT,
                cheque_number TEXT NOT NULL,
                issue_date TEXT NOT NULL,
                due_date TEXT,
                status TEXT NOT NULL CHECK(status IN ('issued','deposited','cleared','bounced','cancelled')),
                bounced_reversal_voucher_id TEXT REFERENCES avelo_vouchers(id) ON DELETE RESTRICT,
                represented_from_cheque_id TEXT REFERENCES avelo_cheques(id) ON DELETE RESTRICT,
                created_at TEXT NOT NULL
            )
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_cheques_company_status ON avelo_cheques(company_id, status, cheque_number)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_cheques_represented_from ON avelo_cheques(represented_from_cheque_id)")

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_cheques_company_insert
            BEFORE INSERT ON avelo_cheques
            FOR EACH ROW
            BEGIN
                SELECT RAISE(ABORT, 'Cheque voucher must belong to the same company')
                WHERE NOT EXISTS (
                    SELECT 1 FROM avelo_vouchers v
                    WHERE v.id = NEW.voucher_id
                      AND v.company_id = NEW.company_id
                );

                SELECT RAISE(ABORT, 'Cheque bounced reversal voucher must belong to the same company')
                WHERE NEW.bounced_reversal_voucher_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM avelo_vouchers v
                    WHERE v.id = NEW.bounced_reversal_voucher_id
                      AND v.company_id = NEW.company_id
                );

                SELECT RAISE(ABORT, 'Represented-from cheque must belong to the same company')
                WHERE NEW.represented_from_cheque_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM avelo_cheques c
                    WHERE c.id = NEW.represented_from_cheque_id
                      AND c.company_id = NEW.company_id
                );
            END;
            """
        )

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_cheques_company_update
            BEFORE UPDATE ON avelo_cheques
            FOR EACH ROW
            BEGIN
                SELECT RAISE(ABORT, 'Cheque voucher must belong to the same company')
                WHERE NOT EXISTS (
                    SELECT 1 FROM avelo_vouchers v
                    WHERE v.id = NEW.voucher_id
                      AND v.company_id = NEW.company_id
                );

                SELECT RAISE(ABORT, 'Cheque bounced reversal voucher must belong to the same company')
                WHERE NEW.bounced_reversal_voucher_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM avelo_vouchers v
                    WHERE v.id = NEW.bounced_reversal_voucher_id
                      AND v.company_id = NEW.company_id
                );

                SELECT RAISE(ABORT, 'Represented-from cheque must belong to the same company')
                WHERE NEW.represented_from_cheque_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM avelo_cheques c
                    WHERE c.id = NEW.represented_from_cheque_id
                      AND c.company_id = NEW.company_id
                );
            END;
            """
        )
    }
}
