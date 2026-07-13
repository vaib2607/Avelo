import Foundation

/// Tally ledger-master parity: mailing details, GST registration profile,
/// and bill-wise/credit-period settings on accounts. All columns are
/// nullable (or defaulted) so existing rows need no backfill.
public struct MigrationV019: Migration {
    public let version: SchemaVersion = .v19
    public let description = "Add ledger master parity columns to accounts"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN mailing_name TEXT;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN mailing_address TEXT;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN state_code TEXT;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN country TEXT;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN gst_registration_type TEXT;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN maintain_billwise INTEGER NOT NULL DEFAULT 0;")
        try db.execute("ALTER TABLE avelo_accounts ADD COLUMN credit_period_days INTEGER;")
    }
}
