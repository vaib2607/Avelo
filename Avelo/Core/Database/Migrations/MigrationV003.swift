import Foundation

public struct MigrationV003: Migration {
    public let version: SchemaVersion = .v3
    public let description: String = "Add PO/SO pending visibility and inventory reorder thresholds."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS avelo_inventory_orders (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES avelo_companies(id),
            order_type TEXT NOT NULL CHECK(order_type IN ('purchaseOrder','salesOrder')),
            number TEXT NOT NULL,
            party_account_id TEXT NOT NULL REFERENCES avelo_accounts(id),
            order_date TEXT NOT NULL,
            expected_date TEXT,
            status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','closed','cancelled')),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(company_id, order_type, number)
        );
        """)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS avelo_inventory_order_lines (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES avelo_companies(id),
            order_id TEXT NOT NULL REFERENCES avelo_inventory_orders(id) ON DELETE RESTRICT,
            item_id TEXT NOT NULL REFERENCES avelo_inventory_items(id),
            quantity INTEGER NOT NULL CHECK(quantity > 0),
            fulfilled_quantity INTEGER NOT NULL DEFAULT 0 CHECK(fulfilled_quantity >= 0),
            unit_rate_paise INTEGER NOT NULL DEFAULT 0 CHECK(unit_rate_paise >= 0),
            created_at TEXT NOT NULL,
            CHECK(fulfilled_quantity <= quantity)
        );
        """)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS avelo_inventory_reorder_levels (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES avelo_companies(id),
            item_id TEXT NOT NULL REFERENCES avelo_inventory_items(id),
            minimum_quantity INTEGER NOT NULL CHECK(minimum_quantity >= 0),
            reorder_quantity INTEGER NOT NULL CHECK(reorder_quantity >= 0),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(company_id, item_id)
        );
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_inventory_orders_company_status ON avelo_inventory_orders(company_id, order_type, status, order_date);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_inventory_order_lines_order ON avelo_inventory_order_lines(order_id);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_inventory_order_lines_item ON avelo_inventory_order_lines(company_id, item_id);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_inventory_reorder_company_item ON avelo_inventory_reorder_levels(company_id, item_id);")
    }
}
