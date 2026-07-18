import Foundation

/// Completes the scratch-data shape required to recover an item-invoice
/// editor without changing financial history or V027's canonical tracks.
public struct MigrationV028: Migration {
    public let version: SchemaVersion = .v28
    public let description = "Persist complete item-invoice draft editor state"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("""
            ALTER TABLE avelo_voucher_drafts
                ADD COLUMN sales_purchase_ledger_id TEXT;
            ALTER TABLE avelo_voucher_drafts
                ADD COLUMN item_lines_json TEXT;
            """)
    }
}
