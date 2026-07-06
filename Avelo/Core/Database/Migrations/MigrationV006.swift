import Foundation

public struct MigrationV006: Migration {
    public let version: SchemaVersion = .v6
    public let description = "Add explicit stock-movement reversal targets for deterministic layer cancellation"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("ALTER TABLE avelo_stock_movements ADD COLUMN reversed_movement_id TEXT REFERENCES avelo_stock_movements(id);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_mov_reversed ON avelo_stock_movements(reversed_movement_id);")
    }
}
