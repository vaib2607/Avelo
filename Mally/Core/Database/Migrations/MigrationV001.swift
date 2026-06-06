import Foundation

public struct MigrationV001: Migration {

    public let version: SchemaVersion = .v1
    public let description: String = "Initial Mally schema: companies, financial years, accounts, groups, voucher types, vouchers, ledger lines, inventory, payroll, audit, sequences, templates, bank reconciliation."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(Self.schemaSQL)
    }

    static let schemaSQL: String = #"""
    -- =====================================================================
    -- Mally v1 schema
    -- =====================================================================

    CREATE TABLE mally_companies (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        address_line1 TEXT,
        address_line2 TEXT,
        city TEXT,
        state TEXT,
        pincode TEXT,
        country TEXT NOT NULL DEFAULT 'India',
        gstin TEXT,
        pan TEXT,
        base_currency TEXT NOT NULL DEFAULT 'INR' CHECK(base_currency = 'INR'),
        is_inventory_enabled INTEGER NOT NULL DEFAULT 0 CHECK(is_inventory_enabled IN (0,1)),
        inventory_link_mode TEXT NOT NULL DEFAULT 'manual' CHECK(inventory_link_mode IN ('manual','autoPrompt','autoSilent')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(length(trim(name)) > 0),
        UNIQUE(name),
        CHECK(length(gstin) = 15 OR gstin IS NULL),
        CHECK(length(pan) = 10 OR pan IS NULL)
    );
    CREATE INDEX idx_mally_companies_name ON mally_companies(name);

    CREATE TABLE mally_financial_years (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        label TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        books_begin_date TEXT NOT NULL,
        is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0,1)),
        is_closed INTEGER NOT NULL DEFAULT 0 CHECK(is_closed IN (0,1)),
        created_at TEXT NOT NULL,
        CHECK(length(trim(label)) > 0),
        UNIQUE(company_id, label)
    );
    CREATE INDEX idx_mally_fy_company ON mally_financial_years(company_id);
    CREATE INDEX idx_mally_fy_dates ON mally_financial_years(company_id, start_date, end_date);

    CREATE TRIGGER trg_mally_fy_no_overlap
    BEFORE INSERT ON mally_financial_years
    FOR EACH ROW
    BEGIN
        SELECT RAISE(ABORT, 'Financial year overlaps an existing year for this company')
        WHERE EXISTS (
            SELECT 1 FROM mally_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND NOT (NEW.end_date < fy.start_date OR NEW.start_date > fy.end_date)
        );
    END;

    CREATE TABLE mally_account_groups (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        parent_group_id TEXT REFERENCES mally_account_groups(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        nature TEXT NOT NULL CHECK(nature IN ('assets','liabilities','income','expense')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        CHECK(length(trim(code)) > 0),
        CHECK(length(trim(name)) > 0),
        UNIQUE(company_id, code)
    );
    CREATE INDEX idx_mally_groups_company ON mally_account_groups(company_id);
    CREATE INDEX idx_mally_groups_parent ON mally_account_groups(parent_group_id);

    CREATE TABLE mally_accounts (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        group_id TEXT NOT NULL REFERENCES mally_account_groups(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        opening_balance_paise INTEGER NOT NULL DEFAULT 0,
        opening_balance_side TEXT NOT NULL DEFAULT 'debit' CHECK(opening_balance_side IN ('debit','credit')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        is_bank_account INTEGER NOT NULL DEFAULT 0 CHECK(is_bank_account IN (0,1)),
        gstin TEXT,
        last_used_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(length(trim(code)) > 0),
        CHECK(length(trim(name)) > 0),
        CHECK(opening_balance_paise >= 0),
        CHECK(length(gstin) = 15 OR gstin IS NULL),
        UNIQUE(company_id, code)
    );
    CREATE INDEX idx_mally_accounts_company ON mally_accounts(company_id);
    CREATE INDEX idx_mally_accounts_group ON mally_accounts(group_id);
    CREATE INDEX idx_mally_accounts_last_used ON mally_accounts(company_id, last_used_at DESC);

    CREATE TRIGGER trg_mally_accounts_group_must_be_leaf
    BEFORE INSERT ON mally_accounts
    FOR EACH ROW
    BEGIN
        SELECT RAISE(ABORT, 'Account must be posted under a leaf group (a group with no child groups)')
        WHERE EXISTS (SELECT 1 FROM mally_account_groups g WHERE g.parent_group_id = NEW.group_id);
    END;

    CREATE TABLE mally_voucher_types (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        code TEXT NOT NULL CHECK(code IN ('journal','sales','purchase','payment','receipt','contra','creditNote','debitNote','opening','payroll')),
        name TEXT NOT NULL,
        abbreviation TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0 CHECK(is_system IN (0,1)),
        affects_inventory INTEGER NOT NULL DEFAULT 0 CHECK(affects_inventory IN (0,1)),
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        CHECK(length(trim(name)) > 0),
        CHECK(length(trim(abbreviation)) > 0),
        UNIQUE(company_id, code)
    );

    CREATE TABLE mally_vouchers (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        financial_year_id TEXT NOT NULL REFERENCES mally_financial_years(id),
        voucher_type_code TEXT NOT NULL,
        number TEXT NOT NULL,
        date TEXT NOT NULL,
        party_account_id TEXT REFERENCES mally_accounts(id),
        narration TEXT NOT NULL DEFAULT '',
        reference TEXT NOT NULL DEFAULT '',
        is_reversal INTEGER NOT NULL DEFAULT 0 CHECK(is_reversal IN (0,1)),
        reversal_of_id TEXT REFERENCES mally_vouchers(id),
        is_posted INTEGER NOT NULL DEFAULT 1 CHECK(is_posted IN (0,1)),
        total_paise INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(length(trim(number)) > 0),
        UNIQUE(company_id, financial_year_id, voucher_type_code, number)
    );
    CREATE INDEX idx_mally_vouchers_company_date ON mally_vouchers(company_id, date);
    CREATE INDEX idx_mally_vouchers_fy ON mally_vouchers(financial_year_id);
    CREATE INDEX idx_mally_vouchers_type ON mally_vouchers(voucher_type_code, date);
    CREATE INDEX idx_mally_vouchers_party ON mally_vouchers(party_account_id);
    CREATE INDEX idx_mally_vouchers_reversal ON mally_vouchers(reversal_of_id);

    CREATE TRIGGER trg_mally_voucher_date_in_fy
    BEFORE INSERT ON mally_vouchers
    FOR EACH ROW
    BEGIN
        SELECT RAISE(ABORT, 'Voucher date is outside its financial year')
        WHERE NOT EXISTS (
            SELECT 1 FROM mally_financial_years fy
            WHERE fy.id = NEW.financial_year_id
              AND fy.company_id = NEW.company_id
              AND NEW.date BETWEEN fy.start_date AND fy.end_date
        );
    END;

    CREATE TRIGGER trg_mally_voucher_fy_locked_insert
    BEFORE INSERT ON mally_vouchers
    FOR EACH ROW
    WHEN (SELECT is_locked FROM mally_financial_years WHERE id = NEW.financial_year_id) = 1
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked; new vouchers are not allowed');
    END;

    CREATE TRIGGER trg_mally_voucher_fy_locked_update
    BEFORE UPDATE ON mally_vouchers
    FOR EACH ROW
    WHEN (SELECT is_locked FROM mally_financial_years WHERE id = OLD.financial_year_id) = 1
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked; voucher edits are not allowed');
    END;

    CREATE TRIGGER trg_mally_voucher_fy_locked_delete
    BEFORE DELETE ON mally_vouchers
    FOR EACH ROW
    WHEN (SELECT is_locked FROM mally_financial_years WHERE id = OLD.financial_year_id) = 1
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked; voucher deletes are not allowed');
    END;

    CREATE TABLE mally_ledger_lines (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        voucher_id TEXT NOT NULL REFERENCES mally_vouchers(id) ON DELETE CASCADE,
        account_id TEXT NOT NULL REFERENCES mally_accounts(id),
        amount_paise INTEGER NOT NULL CHECK(amount_paise > 0),
        side TEXT NOT NULL CHECK(side IN ('debit','credit')),
        tax_code TEXT,
        cost_center TEXT,
        line_order INTEGER NOT NULL
    );
    CREATE INDEX idx_mally_lines_voucher ON mally_ledger_lines(voucher_id, line_order);
    CREATE INDEX idx_mally_lines_account ON mally_ledger_lines(account_id);
    CREATE INDEX idx_mally_lines_company_side ON mally_ledger_lines(company_id, side);

    CREATE TRIGGER trg_mally_lines_fy_locked_insert
    BEFORE INSERT ON mally_ledger_lines
    FOR EACH ROW
    WHEN (SELECT v.financial_year_id FROM mally_vouchers v WHERE v.id = NEW.voucher_id) IN
         (SELECT id FROM mally_financial_years WHERE is_locked = 1)
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked');
    END;

    CREATE TRIGGER trg_mally_lines_fy_locked_update
    BEFORE UPDATE ON mally_ledger_lines
    FOR EACH ROW
    WHEN (SELECT v.financial_year_id FROM mally_vouchers v WHERE v.id = OLD.voucher_id) IN
         (SELECT id FROM mally_financial_years WHERE is_locked = 1)
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked');
    END;

    CREATE TRIGGER trg_mally_lines_fy_locked_delete
    BEFORE DELETE ON mally_ledger_lines
    FOR EACH ROW
    WHEN (SELECT v.financial_year_id FROM mally_vouchers v WHERE v.id = OLD.voucher_id) IN
         (SELECT id FROM mally_financial_years WHERE is_locked = 1)
    BEGIN
        SELECT RAISE(ABORT, 'Financial year is locked');
    END;

    CREATE TABLE mally_inventory_items (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        valuation_method TEXT NOT NULL DEFAULT 'fifo' CHECK(valuation_method IN ('fifo','weightedAverage')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        opening_quantity REAL NOT NULL DEFAULT 0,
        opening_rate_paise INTEGER NOT NULL DEFAULT 0,
        gst_rate REAL NOT NULL DEFAULT 0,
        barcode TEXT,
        hsn_sac TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
        linked_account_id TEXT REFERENCES mally_accounts(id),
        created_at TEXT NOT NULL,
        CHECK(length(trim(code)) > 0),
        CHECK(length(trim(name)) > 0),
        UNIQUE(company_id, code)
    );

    CREATE TABLE mally_stock_movements (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        item_id TEXT NOT NULL REFERENCES mally_inventory_items(id),
        voucher_id TEXT REFERENCES mally_vouchers(id),
        date TEXT NOT NULL,
        movement_type TEXT NOT NULL CHECK(movement_type IN ('in','out','adjustment','opening','purchase','purchaseReturn','sale','saleReturn','adjustmentIn','adjustmentOut')),
        quantity REAL NOT NULL DEFAULT 0,
        unit_cost_paise INTEGER NOT NULL DEFAULT 0,
        total_value_paise INTEGER NOT NULL DEFAULT 0,
        reference_voucher_number TEXT,
        reason TEXT,
        created_at TEXT NOT NULL
    );
    CREATE INDEX idx_mally_mov_item_date ON mally_stock_movements(item_id, date);
    CREATE INDEX idx_mally_mov_company_date ON mally_stock_movements(company_id, date);
    CREATE INDEX idx_mally_mov_voucher ON mally_stock_movements(voucher_id);

    CREATE TABLE mally_payroll_employees (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        designation TEXT,
        pan TEXT,
        bank_account_id TEXT REFERENCES mally_accounts(id),
        base_salary_paise INTEGER NOT NULL DEFAULT 0,
        basic_paise INTEGER NOT NULL DEFAULT 0,
        hra_paise INTEGER NOT NULL DEFAULT 0,
        other_allowances_paise INTEGER NOT NULL DEFAULT 0,
        bank_account TEXT,
        ifsc TEXT,
        pf_applicable INTEGER NOT NULL DEFAULT 0 CHECK(pf_applicable IN (0,1)),
        esi_applicable INTEGER NOT NULL DEFAULT 0 CHECK(esi_applicable IN (0,1)),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        joined_on TEXT NOT NULL,
        end_date TEXT,
        created_at TEXT NOT NULL,
        CHECK(length(trim(code)) > 0),
        CHECK(length(trim(name)) > 0),
        UNIQUE(company_id, code)
    );

    CREATE TABLE mally_payroll_entries (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        employee_id TEXT NOT NULL REFERENCES mally_payroll_employees(id),
        financial_year_id TEXT NOT NULL REFERENCES mally_financial_years(id),
        voucher_id TEXT REFERENCES mally_vouchers(id),
        month INTEGER NOT NULL CHECK(month BETWEEN 1 AND 12),
        year INTEGER NOT NULL CHECK(year BETWEEN 2000 AND 9999),
        working_days INTEGER NOT NULL DEFAULT 0,
        paid_days INTEGER NOT NULL DEFAULT 0,
        basic_paise INTEGER NOT NULL DEFAULT 0,
        hra_paise INTEGER NOT NULL DEFAULT 0,
        other_allowances_paise INTEGER NOT NULL DEFAULT 0,
        overtime_paise INTEGER NOT NULL DEFAULT 0,
        gross_paise INTEGER NOT NULL DEFAULT 0,
        deductions_paise INTEGER NOT NULL DEFAULT 0,
        net_paise INTEGER NOT NULL DEFAULT 0,
        pf_applicable INTEGER NOT NULL DEFAULT 0,
        esi_applicable INTEGER NOT NULL DEFAULT 0,
        posted_at TEXT NOT NULL
    );
    CREATE INDEX idx_mally_payroll_emp_period ON mally_payroll_entries(employee_id, year, month);
    CREATE INDEX idx_mally_payroll_company_period ON mally_payroll_entries(company_id, year, month);

    CREATE TABLE mally_audit_events (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        timestamp TEXT NOT NULL,
        actor TEXT NOT NULL DEFAULT 'user',
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        snapshot_before_json TEXT,
        snapshot_after_json TEXT,
        reason TEXT,
        CHECK(length(trim(action)) > 0),
        CHECK(length(trim(entity_type)) > 0),
        CHECK(length(trim(entity_id)) > 0)
    );
    CREATE INDEX idx_mally_audit_entity ON mally_audit_events(company_id, entity_type, entity_id);
    CREATE INDEX idx_mally_audit_time ON mally_audit_events(company_id, timestamp);

    CREATE TRIGGER trg_mally_audit_no_update
    BEFORE UPDATE ON mally_audit_events
    BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;

    CREATE TRIGGER trg_mally_audit_no_delete
    BEFORE DELETE ON mally_audit_events
    BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;

    CREATE TABLE mally_voucher_sequences (
        company_id TEXT NOT NULL,
        financial_year_id TEXT NOT NULL,
        voucher_type_code TEXT NOT NULL,
        last_number INTEGER NOT NULL DEFAULT 0,
        prefix TEXT,
        suffix TEXT,
        padding INTEGER NOT NULL DEFAULT 5,
        PRIMARY KEY(company_id, financial_year_id, voucher_type_code)
    );

    CREATE TABLE mally_voucher_templates (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        name TEXT NOT NULL,
        voucher_type_code TEXT NOT NULL,
        description TEXT,
        template_lines_json TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        CHECK(length(trim(name)) > 0),
        UNIQUE(company_id, name)
    );

    CREATE TABLE mally_bank_reconciliations (
        id TEXT NOT NULL PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES mally_companies(id),
        bank_account_id TEXT NOT NULL REFERENCES mally_accounts(id),
        voucher_id TEXT NOT NULL REFERENCES mally_vouchers(id),
        statement_date TEXT NOT NULL,
        statement_amount_paise INTEGER NOT NULL,
        is_cleared INTEGER NOT NULL DEFAULT 0 CHECK(is_cleared IN (0,1)),
        cleared_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(voucher_id)
    );
    CREATE INDEX idx_mally_br_account_cleared ON mally_bank_reconciliations(bank_account_id, is_cleared);

    CREATE TABLE mally_bank_statement_lines (
        id TEXT NOT NULL PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES mally_accounts(id),
        date TEXT NOT NULL,
        amount_paise INTEGER NOT NULL,
        narration TEXT NOT NULL DEFAULT '',
        is_cleared INTEGER NOT NULL DEFAULT 0 CHECK(is_cleared IN (0,1)),
        created_at TEXT NOT NULL
    );
    CREATE INDEX idx_mally_bsl_account_date ON mally_bank_statement_lines(account_id, date);

    CREATE TABLE mally_migrations (
        version INTEGER NOT NULL PRIMARY KEY,
        applied_at TEXT NOT NULL,
        description TEXT NOT NULL
    );
    """#
}
