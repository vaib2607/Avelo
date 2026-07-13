import Foundation

/// GST fields on stock items + a structured item-invoice line table (Tally
/// item-invoice mode). Item lines are a separate table from
/// `avelo_ledger_lines` because ledger lines carry no item/quantity data —
/// posting still produces normal ledger lines (party, sales/purchase, duty)
/// via the existing voucher-posting path; these rows are the audit trail
/// linking a voucher back to what was actually sold/bought.
public struct MigrationV020: Migration {
    public let version: SchemaVersion = .v20
    public let description = "Add item GST fields and voucher item-invoice lines"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN hsn_code TEXT;")
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN gst_rate_bps INTEGER;")
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN gst_cess_rate_bps INTEGER;")
        try db.execute("ALTER TABLE avelo_inventory_items ADD COLUMN gst_taxability TEXT NOT NULL DEFAULT 'taxable' CHECK(gst_taxability IN ('taxable','exempt','nilRated'));")

        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS avelo_voucher_item_lines (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                voucher_id TEXT NOT NULL REFERENCES avelo_vouchers(id) ON DELETE CASCADE,
                item_id TEXT NOT NULL REFERENCES avelo_inventory_items(id) ON DELETE RESTRICT,
                quantity INTEGER NOT NULL CHECK(quantity > 0),
                rate_paise INTEGER NOT NULL CHECK(rate_paise >= 0),
                taxable_value_paise INTEGER NOT NULL CHECK(taxable_value_paise >= 0),
                hsn_code TEXT,
                gst_rate_bps INTEGER,
                cgst_paise INTEGER NOT NULL DEFAULT 0,
                sgst_paise INTEGER NOT NULL DEFAULT 0,
                igst_paise INTEGER NOT NULL DEFAULT 0,
                cess_paise INTEGER NOT NULL DEFAULT 0,
                line_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            """
        )
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_voucher_item_lines_voucher ON avelo_voucher_item_lines(voucher_id, line_order);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_voucher_item_lines_company_item ON avelo_voucher_item_lines(company_id, item_id);")

        try db.execute(
            """
            CREATE TRIGGER IF NOT EXISTS trg_avelo_voucher_item_lines_company_insert
            BEFORE INSERT ON avelo_voucher_item_lines
            FOR EACH ROW
            WHEN NOT EXISTS (
                SELECT 1 FROM avelo_vouchers v
                WHERE v.id = NEW.voucher_id AND v.company_id = NEW.company_id
            ) OR NOT EXISTS (
                SELECT 1 FROM avelo_inventory_items i
                WHERE i.id = NEW.item_id AND i.company_id = NEW.company_id
            )
            BEGIN
                SELECT RAISE(ABORT, 'Voucher item line references must belong to the same company.');
            END;
            """
        )
    }
}
