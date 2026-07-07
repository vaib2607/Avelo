import Foundation

public struct MigrationV017: Migration {
    public let version: SchemaVersion = .v17
    public let description = "Add persisted bill of materials tables with company guards"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_boms (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                assembly_item_id TEXT NOT NULL UNIQUE REFERENCES avelo_inventory_items(id) ON DELETE RESTRICT,
                output_quantity REAL NOT NULL CHECK(output_quantity > 0),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_boms_company_assembly ON avelo_boms(company_id, assembly_item_id);")

        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_bom_components (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                bom_id TEXT NOT NULL REFERENCES avelo_boms(id) ON DELETE CASCADE,
                component_item_id TEXT NOT NULL REFERENCES avelo_inventory_items(id) ON DELETE RESTRICT,
                quantity REAL NOT NULL CHECK(quantity > 0),
                line_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(bom_id, component_item_id, line_order)
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bom_components_bom_order ON avelo_bom_components(bom_id, line_order, id);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_bom_components_company_component ON avelo_bom_components(company_id, component_item_id);")

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_boms_company_insert
            BEFORE INSERT ON avelo_boms
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_inventory_items i
                WHERE i.id = NEW.assembly_item_id AND i.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'BOM assembly item must belong to the same company.');
            END;
            """
        )

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_boms_company_update
            BEFORE UPDATE ON avelo_boms
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_inventory_items i
                WHERE i.id = NEW.assembly_item_id AND i.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'BOM assembly item must belong to the same company.');
            END;
            """
        )

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_bom_components_company_insert
            BEFORE INSERT ON avelo_bom_components
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_boms b
                WHERE b.id = NEW.bom_id AND b.company_id = NEW.company_id
            ) OR NOT EXISTS (
                SELECT 1 FROM avelo_inventory_items i
                WHERE i.id = NEW.component_item_id AND i.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'BOM component references must belong to the same company.');
            END;
            """
        )

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_bom_components_company_update
            BEFORE UPDATE ON avelo_bom_components
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_boms b
                WHERE b.id = NEW.bom_id AND b.company_id = NEW.company_id
            ) OR NOT EXISTS (
                SELECT 1 FROM avelo_inventory_items i
                WHERE i.id = NEW.component_item_id AND i.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'BOM component references must belong to the same company.');
            END;
            """
        )
    }
}
