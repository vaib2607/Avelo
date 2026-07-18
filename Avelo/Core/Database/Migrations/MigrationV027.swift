import Foundation

/// Establishes the canonical dual-track posting tables. Legacy tables remain
/// read-only forensic history after this migration; subsequent repositories
/// read and write only the `trn_*` tracks.
public struct MigrationV027: Migration {
    public let version: SchemaVersion = .v27
    public let description = "Establish canonical accounting and inventory transaction tracks"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        // Drafts are scratch state, but their entry mode must survive crash
        // recovery so a recovered item invoice is never silently reopened as
        // a ledger voucher. Existing rows intentionally default to ledger.
        try db.execute("ALTER TABLE avelo_voucher_drafts ADD COLUMN entry_mode TEXT NOT NULL DEFAULT 'ledger' CHECK(entry_mode IN ('ledger', 'itemInvoice'));")
        try db.execute("ALTER TABLE avelo_voucher_item_lines ADD COLUMN quantity_numerator INTEGER;")
        try db.execute("ALTER TABLE avelo_voucher_item_lines ADD COLUMN quantity_denominator INTEGER;")
        try db.execute("UPDATE avelo_voucher_item_lines SET quantity_numerator = quantity, quantity_denominator = 1 WHERE quantity_numerator IS NULL OR quantity_denominator IS NULL;")
        try db.execute(
            """
            CREATE TABLE avelo_inventory_locations (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
                created_at TEXT NOT NULL,
                UNIQUE(company_id, code)
            );

            INSERT INTO avelo_inventory_locations (id, company_id, code, name, created_at)
            SELECT lower(hex(randomblob(16))), id, 'MAIN', 'Main', CURRENT_TIMESTAMP
            FROM avelo_companies;

            CREATE TRIGGER trg_avelo_inventory_locations_seed_main
            AFTER INSERT ON avelo_companies
            FOR EACH ROW
            BEGIN
                INSERT INTO avelo_inventory_locations (id, company_id, code, name, created_at)
                VALUES (lower(hex(randomblob(16))), NEW.id, 'MAIN', 'Main', CURRENT_TIMESTAMP);
            END;

            CREATE TABLE trn_accounting (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                voucher_id TEXT NOT NULL REFERENCES avelo_vouchers(id) ON DELETE RESTRICT,
                ledger_id TEXT NOT NULL REFERENCES avelo_accounts(id) ON DELETE RESTRICT,
                amount_paise INTEGER NOT NULL CHECK(amount_paise > 0),
                debit_or_credit TEXT NOT NULL CHECK(debit_or_credit IN ('debit', 'credit')),
                tax_code TEXT,
                cost_center TEXT,
                line_order INTEGER NOT NULL CHECK(line_order >= 0),
                created_at TEXT NOT NULL,
                UNIQUE(voucher_id, line_order)
            );
            CREATE INDEX idx_trn_accounting_voucher ON trn_accounting(voucher_id, line_order);
            CREATE INDEX idx_trn_accounting_account ON trn_accounting(ledger_id);
            CREATE INDEX idx_trn_accounting_company_side ON trn_accounting(company_id, debit_or_credit);
            CREATE VIEW trn_accounting_compat AS
            SELECT id, company_id, voucher_id, ledger_id AS account_id, amount_paise,
                   debit_or_credit AS side, tax_code, cost_center, line_order
            FROM trn_accounting;

            CREATE TABLE trn_inventory (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                voucher_id TEXT REFERENCES avelo_vouchers(id) ON DELETE RESTRICT,
                stock_item_id TEXT NOT NULL REFERENCES avelo_inventory_items(id) ON DELETE RESTRICT,
                warehouse_location_id TEXT NOT NULL REFERENCES avelo_inventory_locations(id) ON DELETE RESTRICT,
                item_line_id TEXT REFERENCES avelo_voucher_item_lines(id) ON DELETE RESTRICT,
                reversal_of_inventory_id TEXT REFERENCES trn_inventory(id) ON DELETE RESTRICT,
                date TEXT NOT NULL,
                movement_type TEXT NOT NULL CHECK(movement_type IN ('in', 'out', 'adjustment')),
                quantity_numerator INTEGER NOT NULL CHECK(quantity_numerator > 0),
                quantity_denominator INTEGER NOT NULL CHECK(quantity_denominator > 0),
                entered_unit TEXT,
                unit_cost_paise INTEGER NOT NULL CHECK(unit_cost_paise >= 0),
                base_value_paise INTEGER NOT NULL CHECK(base_value_paise >= 0),
                landed_cost_paise INTEGER NOT NULL DEFAULT 0 CHECK(landed_cost_paise >= 0),
                reference_voucher_number TEXT,
                reason TEXT,
                created_at TEXT NOT NULL
            );
            CREATE INDEX idx_trn_inventory_item_date ON trn_inventory(stock_item_id, date);
            CREATE INDEX idx_trn_inventory_company_date ON trn_inventory(company_id, date);
            CREATE INDEX idx_trn_inventory_voucher ON trn_inventory(voucher_id);
            CREATE VIEW trn_inventory_compat AS
            SELECT id, company_id, stock_item_id AS item_id, voucher_id, date, movement_type,
                   quantity_numerator AS quantity, quantity_numerator, quantity_denominator,
                   entered_unit, unit_cost_paise,
                   base_value_paise + landed_cost_paise AS total_value_paise,
                   reversal_of_inventory_id AS reversed_movement_id,
                   reference_voucher_number, reason, created_at
            FROM trn_inventory;

            CREATE TABLE trn_inventory_cost_allocations (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                accounting_id TEXT NOT NULL REFERENCES trn_accounting(id) ON DELETE RESTRICT,
                inventory_id TEXT NOT NULL REFERENCES trn_inventory(id) ON DELETE RESTRICT,
                allocated_paise INTEGER NOT NULL CHECK(allocated_paise > 0),
                created_at TEXT NOT NULL,
                UNIQUE(accounting_id, inventory_id)
            );

            INSERT INTO trn_accounting
                (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, tax_code, cost_center, line_order, created_at)
            SELECT l.id, l.company_id, l.voucher_id, l.account_id, l.amount_paise, l.side, l.tax_code, l.cost_center, l.line_order, v.created_at
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id;

            INSERT INTO trn_inventory
                (id, company_id, voucher_id, stock_item_id, warehouse_location_id, date, movement_type,
                 quantity_numerator, quantity_denominator, entered_unit, unit_cost_paise, base_value_paise,
                 landed_cost_paise, reversal_of_inventory_id, reference_voucher_number, reason, created_at)
            SELECT m.id, m.company_id, m.voucher_id, m.item_id,
                   (SELECT l.id FROM avelo_inventory_locations l WHERE l.company_id = m.company_id AND l.code = 'MAIN'),
                   m.date, m.movement_type,
                   COALESCE(m.quantity_numerator, m.quantity), COALESCE(m.quantity_denominator, 1), m.entered_unit,
                   m.unit_cost_paise, m.total_value_paise, 0, m.reversed_movement_id,
                   m.reference_voucher_number, m.reason, m.created_at
            FROM avelo_stock_movements m;
            """
        )

        try createIntegrityTriggers(db)
        try verifyBackfill(db)
    }

    private func createIntegrityTriggers(_ db: SQLiteDatabase) throws {
        let triggers = [
            ("trg_trn_accounting_company_insert", "INSERT", "NEW"),
            ("trg_trn_accounting_company_update", "UPDATE", "NEW")
        ]
        for (name, timing, ref) in triggers {
            try db.execute("""
                CREATE TRIGGER \(name) BEFORE \(timing) ON trn_accounting FOR EACH ROW BEGIN
                    SELECT RAISE(ABORT, 'Accounting references must belong to the same company')
                    WHERE NOT EXISTS (SELECT 1 FROM avelo_vouchers v WHERE v.id = \(ref).voucher_id AND v.company_id = \(ref).company_id)
                       OR NOT EXISTS (SELECT 1 FROM avelo_accounts a WHERE a.id = \(ref).ledger_id AND a.company_id = \(ref).company_id);
                END;
                """)
        }
        for (name, timing, ref) in [("trg_trn_inventory_company_insert", "INSERT", "NEW"), ("trg_trn_inventory_company_update", "UPDATE", "NEW")] {
            try db.execute("""
                CREATE TRIGGER \(name) BEFORE \(timing) ON trn_inventory FOR EACH ROW BEGIN
                    SELECT RAISE(ABORT, 'Inventory references must belong to the same company')
                    WHERE NOT EXISTS (SELECT 1 FROM avelo_inventory_items i WHERE i.id = \(ref).stock_item_id AND i.company_id = \(ref).company_id)
                       OR NOT EXISTS (SELECT 1 FROM avelo_inventory_locations l WHERE l.id = \(ref).warehouse_location_id AND l.company_id = \(ref).company_id)
                       OR (\(ref).voucher_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM avelo_vouchers v WHERE v.id = \(ref).voucher_id AND v.company_id = \(ref).company_id))
                       OR (\(ref).item_line_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM avelo_voucher_item_lines il WHERE il.id = \(ref).item_line_id AND il.company_id = \(ref).company_id AND il.voucher_id = \(ref).voucher_id))
                       OR (\(ref).reversal_of_inventory_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM trn_inventory prior WHERE prior.id = \(ref).reversal_of_inventory_id AND prior.company_id = \(ref).company_id));
                END;
                """)
        }
        for (name, timing, ref) in [("trg_trn_inventory_cost_allocations_company_insert", "INSERT", "NEW"), ("trg_trn_inventory_cost_allocations_company_update", "UPDATE", "NEW")] {
            try db.execute("""
                CREATE TRIGGER \(name) BEFORE \(timing) ON trn_inventory_cost_allocations FOR EACH ROW BEGIN
                    SELECT RAISE(ABORT, 'Inventory cost allocations must remain within one company')
                    WHERE NOT EXISTS (SELECT 1 FROM trn_accounting a WHERE a.id = \(ref).accounting_id AND a.company_id = \(ref).company_id)
                       OR NOT EXISTS (SELECT 1 FROM trn_inventory i WHERE i.id = \(ref).inventory_id AND i.company_id = \(ref).company_id);
                END;
                """)
        }
    }

    private func verifyBackfill(_ db: SQLiteDatabase) throws {
        let oldLines = try db.queryOne("SELECT COUNT(*) FROM avelo_ledger_lines") { $0.int(0) } ?? 0
        let newLines = try db.queryOne("SELECT COUNT(*) FROM trn_accounting") { $0.int(0) } ?? 0
        let oldMovements = try db.queryOne("SELECT COUNT(*) FROM avelo_stock_movements") { $0.int(0) } ?? 0
        let newMovements = try db.queryOne("SELECT COUNT(*) FROM trn_inventory") { $0.int(0) } ?? 0
        guard oldLines == newLines, oldMovements == newMovements else {
            throw AppError.database(.migrationFailed("V027 backfill row counts do not reconcile."))
        }
        let imbalance = try db.queryOne("""
            SELECT COUNT(*) FROM (
                SELECT voucher_id,
                       SUM(CASE WHEN debit_or_credit = 'debit' THEN amount_paise ELSE 0 END) AS debit,
                       SUM(CASE WHEN debit_or_credit = 'credit' THEN amount_paise ELSE 0 END) AS credit
                FROM trn_accounting GROUP BY voucher_id HAVING debit != credit
            )
            """) { $0.int(0) } ?? 0
        guard imbalance == 0 else {
            throw AppError.database(.migrationFailed("V027 found unbalanced historical vouchers."))
        }
        try verifyCanonicalIdentifiers(db)
    }

    /// SQLite accepts arbitrary TEXT primary keys. Canonical records are Swift
    /// UUID-backed, so reject a malformed legacy identifier before it becomes
    /// durable canonical history.
    private func verifyCanonicalIdentifiers(_ db: SQLiteDatabase) throws {
        let accountingValues: [(String, String)] = try db.query(
            "SELECT id, company_id FROM trn_accounting"
        ) { row in
            (try row.requiredText("id"), try row.requiredText("company_id"))
        }
        let inventoryValues: [(String, String)] = try db.query(
            "SELECT id, company_id FROM trn_inventory"
        ) { row in
            (try row.requiredText("id"), try row.requiredText("company_id"))
        }
        for (id, companyId) in accountingValues + inventoryValues {
            guard UUID(uuidString: id) != nil, UUID(uuidString: companyId) != nil else {
                throw AppError.database(.migrationFailed("V027 found malformed canonical identifier in legacy history."))
            }
        }
    }
}
