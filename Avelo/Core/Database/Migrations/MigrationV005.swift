import Foundation

public struct MigrationV005: Migration {
    public let version: SchemaVersion = .v5
    public let description: String = "Add exact alternate-UOM definitions and rational stock quantities."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN alternate_unit TEXT;")
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN alt_unit_base_numerator INTEGER;")
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN alt_unit_base_denominator INTEGER;")

        try db.execute("ALTER TABLE avelo_stock_movements ADD COLUMN quantity_numerator INTEGER;")
        try db.execute("ALTER TABLE avelo_stock_movements ADD COLUMN quantity_denominator INTEGER;")
        try db.execute("ALTER TABLE avelo_stock_movements ADD COLUMN entered_unit TEXT;")

        try db.execute("""
            UPDATE avelo_stock_movements
               SET quantity_numerator = quantity,
                   quantity_denominator = 1
             WHERE quantity_numerator IS NULL
                OR quantity_denominator IS NULL
        """)
    }
}
