import Foundation

/// Adds the cash/bank ledger column to voucher drafts so single-entry-mode
/// autosave (Contra/Payment/Receipt) survives crash recovery. Nullable and
/// unreferenced like the table's other scratch columns (AVL-P0-018) — drafts
/// are never validated or posted from, so no FK/ownership trigger is needed.
public struct MigrationV021: Migration {
    public let version: SchemaVersion = .v21
    public let description = "Add account_ledger_id to voucher drafts for single-entry-mode recovery"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("ALTER TABLE avelo_voucher_drafts ADD COLUMN account_ledger_id TEXT;")
    }
}
