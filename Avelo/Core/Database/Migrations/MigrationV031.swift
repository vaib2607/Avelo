import Foundation

/// Adds Alt+2 duplicate-voucher lineage: `duplicated_from_voucher_id`
/// records which voucher a duplicate was created from, the same way
/// `reversal_of_id`/`cancellation_voucher_id` already record Reverse/Cancel
/// lineage. Additive and forward-only; `NULL` for every existing voucher.
public struct MigrationV031: Migration {
    public let version: SchemaVersion = .v31
    public let description = "Add duplicate-voucher lineage tracking"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("""
            ALTER TABLE avelo_vouchers
                ADD COLUMN duplicated_from_voucher_id TEXT REFERENCES avelo_vouchers(id);
            CREATE INDEX idx_avelo_vouchers_duplicated_from ON avelo_vouchers(duplicated_from_voucher_id);
            ALTER TABLE avelo_voucher_drafts
                ADD COLUMN duplicated_from_voucher_id TEXT;
            """)
    }
}
