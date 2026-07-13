import XCTest
@testable import Avelo

final class SchemaDriftTests: XCTestCase {

    private func migratedDB() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)
        return db
    }

    private func userTables(in db: SQLiteDatabase) throws -> [String] {
        try db.query(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'table'
              AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        ) { $0.text("name") }
    }

    private func columns(_ table: String, in db: SQLiteDatabase) throws -> [String] {
        try db.query("PRAGMA table_info(\(table))") { $0.text("name") }
    }

    private func createSQL(_ table: String, in db: SQLiteDatabase) throws -> String {
        try XCTUnwrap(
            db.queryOne(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                bind: [.text(table)]
            ) { $0.text("sql") }
        )
    }

    func testMigratedCompanyDatabaseHasOnlyFrozenTables() throws {
        let db = try migratedDB()
        let expected = [
            "avelo_account_groups",
            "avelo_accounts",
            "avelo_audit_events",
            "avelo_bank_reconciliations",
            "avelo_bank_statement_lines",
            "avelo_bill_allocations",
            "avelo_bom_components",
            "avelo_boms",
            "avelo_cheques",
            "avelo_companies",
            "avelo_financial_year_opening_balances",
            "avelo_financial_years",
            "avelo_inventory_items",
            "avelo_inventory_order_lines",
            "avelo_inventory_orders",
            "avelo_inventory_reorder_levels",
            "avelo_ledger_lines",
            "avelo_migrations",
            "avelo_payroll_employees",
            "avelo_payroll_entries",
            "avelo_stock_movements",
            "avelo_voucher_drafts",
            "avelo_voucher_item_lines",
            "avelo_voucher_sequences",
            "avelo_voucher_templates",
            "avelo_voucher_types",
            "avelo_vouchers"
        ]

        XCTAssertEqual(try userTables(in: db), expected)
    }

    func testFrozenInventoryAndPayrollColumnsMatchMigration() throws {
        let db = try migratedDB()

        XCTAssertEqual(try columns("avelo_inventory_items", in: db), [
            "id",
            "company_id",
            "code",
            "name",
            "unit",
            "valuation_method",
            "is_active",
            "created_at",
            "alternate_unit",
            "alt_unit_base_numerator",
            "alt_unit_base_denominator",
            "hsn_code",
            "gst_rate_bps",
            "gst_cess_rate_bps",
            "gst_taxability"
        ])
        XCTAssertEqual(try columns("avelo_vouchers", in: db), [
            "id",
            "company_id",
            "financial_year_id",
            "voucher_type_code",
            "number",
            "date",
            "party_account_id",
            "narration",
            "status",
            "is_reversal",
            "reversal_of_id",
            "cancelled_at",
            "cancelled_by",
            "cancellation_reason",
            "cancellation_voucher_id",
            "is_posted",
            "total_paise",
            "created_at",
            "updated_at"
        ])
        XCTAssertEqual(try columns("avelo_bill_allocations", in: db), [
            "id",
            "company_id",
            "voucher_id",
            "party_account_id",
            "kind",
            "reference_number",
            "allocated_paise",
            "created_at"
        ])
        XCTAssertEqual(try columns("avelo_cheques", in: db), [
            "id",
            "company_id",
            "voucher_id",
            "cheque_number",
            "issue_date",
            "due_date",
            "status",
            "bounced_reversal_voucher_id",
            "represented_from_cheque_id",
            "created_at"
        ])
        XCTAssertEqual(try columns("avelo_boms", in: db), [
            "id",
            "company_id",
            "assembly_item_id",
            "output_quantity",
            "created_at",
            "updated_at"
        ])
        XCTAssertEqual(try columns("avelo_bom_components", in: db), [
            "id",
            "company_id",
            "bom_id",
            "component_item_id",
            "quantity",
            "line_order"
        ])
        XCTAssertEqual(try columns("avelo_audit_events", in: db), [
            "id",
            "company_id",
            "timestamp",
            "actor",
            "action",
            "entity_type",
            "entity_id",
            "snapshot_before_json",
            "snapshot_after_json",
            "reason",
            "sequence_number",
            "previous_chain_hmac",
            "chain_hmac"
        ])
        XCTAssertEqual(try columns("avelo_stock_movements", in: db), [
            "id",
            "company_id",
            "item_id",
            "voucher_id",
            "date",
            "movement_type",
            "quantity",
            "unit_cost_paise",
            "total_value_paise",
            "reference_voucher_number",
            "reason",
            "created_at",
            "quantity_numerator",
            "quantity_denominator",
            "entered_unit",
            "reversed_movement_id"
        ])
        XCTAssertEqual(try columns("avelo_inventory_orders", in: db), [
            "id",
            "company_id",
            "order_type",
            "number",
            "party_account_id",
            "order_date",
            "expected_date",
            "status",
            "created_at",
            "updated_at"
        ])
        XCTAssertEqual(try columns("avelo_inventory_order_lines", in: db), [
            "id",
            "company_id",
            "order_id",
            "item_id",
            "quantity",
            "fulfilled_quantity",
            "unit_rate_paise",
            "created_at"
        ])
        XCTAssertEqual(try columns("avelo_inventory_reorder_levels", in: db), [
            "id",
            "company_id",
            "item_id",
            "minimum_quantity",
            "reorder_quantity",
            "created_at",
            "updated_at"
        ])
        XCTAssertEqual(try columns("avelo_payroll_employees", in: db), [
            "id",
            "company_id",
            "code",
            "name",
            "designation",
            "pan",
            "bank_account_id",
            "base_salary_paise",
            "is_active",
            "joined_on",
            "end_date",
            "created_at"
        ])
        XCTAssertEqual(try columns("avelo_voucher_item_lines", in: db), [
            "id",
            "company_id",
            "voucher_id",
            "item_id",
            "quantity",
            "rate_paise",
            "taxable_value_paise",
            "hsn_code",
            "gst_rate_bps",
            "cgst_paise",
            "sgst_paise",
            "igst_paise",
            "cess_paise",
            "line_order",
            "created_at"
        ])
        XCTAssertEqual(try columns("avelo_payroll_entries", in: db), [
            "id",
            "company_id",
            "employee_id",
            "financial_year_id",
            "voucher_id",
            "month",
            "year",
            "gross_paise",
            "deductions_paise",
            "net_paise",
            "posted_at"
        ])
    }

    func testFrozenMovementTypeCheckMatchesMigration() throws {
        let sql = try createSQL("avelo_stock_movements", in: migratedDB())

        XCTAssertTrue(sql.contains("movement_type IN ('in','out','adjustment')"), sql)
        XCTAssertFalse(sql.contains("purchaseReturn"), sql)
        XCTAssertFalse(sql.contains("saleReturn"), sql)
        XCTAssertFalse(sql.contains("adjustmentIn"), sql)
        XCTAssertFalse(sql.contains("adjustmentOut"), sql)
        XCTAssertFalse(sql.contains("opening"), sql)
    }

    func testFrozenAuditActionCheckMatchesNamingFreeze() throws {
        let sql = try createSQL("avelo_audit_events", in: migratedDB())
        let frozenActions = [
            "companyCreated",
            "companyUpdated",
            "financialYearCreated",
            "financialYearLocked",
            "financialYearClosed",
            "accountCreated",
            "accountUpdated",
            "accountDisabled",
            "voucherPosted",
            "voucherEdited",
            "voucherReversed",
            "voucherCancelled",
            "openingBalancePosted",
            "stockItemCreated",
            "stockItemUpdated",
            "stockItemDisabled",
            "stockMovementPosted",
            "stockMovementReversed",
            "payrollEmployeeCreated",
            "payrollEmployeeUpdated",
            "payrollEmployeeTerminated",
            "salaryPosted",
            "backupExported",
            "backupImported",
            "companySwitched",
            "financialYearSwitched"
        ]

        for action in frozenActions {
            XCTAssertTrue(sql.contains("'\(action)'"), "Missing frozen audit action \(action)")
        }
        let nonFrozenActions = [
            "inventoryModeChanged",
            "fyUnlocked",
            "inventoryEnabled",
            "itemCreated",
            "itemUpdated",
            "itemArchived",
            "itemAccountLinked",
            "stockMoved",
            "employeeCreated",
            "employeeUpdated",
            "employeeDeactivated",
            "payrollEntryPosted",
            "bankStatementImported",
            "bankStatementLineCleared",
            "bankReconciled"
        ]
        for action in nonFrozenActions {
            XCTAssertFalse(sql.contains("'\(action)'"), "Non-frozen audit action is present: \(action)")
        }
        XCTAssertTrue(sql.contains("sequence_number INTEGER NOT NULL"), sql)
        XCTAssertTrue(sql.contains("previous_chain_hmac TEXT"), sql)
        XCTAssertTrue(sql.contains("chain_hmac TEXT NOT NULL"), sql)
    }

    func testMigrationV008BackfillsRoundOffLedgerOncePerCompany() throws {
        let db = try migratedDB()
        let companyId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())

        try db.execute(
            "INSERT INTO avelo_companies (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [.text(companyId.uuidString), .text("Round Off Co"), .text(now), .text(now)]
        )
        try db.execute(
            """
            INSERT INTO avelo_account_groups
            (id, company_id, code, name, nature, sort_order, created_at)
            VALUES (?, ?, 'INDIRECT_EXPENSE', 'Indirect Expenses', 'expense', 1, ?)
            """,
            [.text(UUID().uuidString), .text(companyId.uuidString), .text(now)]
        )

        try MigrationV008().up(db)
        try MigrationV008().up(db)

        let count = try db.queryOne(
            "SELECT COUNT(*) FROM avelo_accounts WHERE company_id = ? AND code = 'ROUND_OFF'",
            bind: [.text(companyId.uuidString)]
        ) { $0.int(0) } ?? 0
        XCTAssertEqual(count, 1)
    }

    func testMigrationV010AddsFinancialYearOverlapUpdateTrigger() throws {
        let db = try migratedDB()
        let triggerSQL = try XCTUnwrap(
            db.queryOne(
                "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_avelo_fy_no_overlap_update'"
            ) { $0.text(0) }
        )

        XCTAssertTrue(triggerSQL.localizedCaseInsensitiveContains("before update on avelo_financial_years"))
        XCTAssertTrue(triggerSQL.localizedCaseInsensitiveContains("financial year overlaps an existing year for this company"))
    }

    func testMigrationV011AddsExpandedFiscalLockTriggers() throws {
        let db = try migratedDB()
        let triggerNames = try db.query(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_avelo_%fy_locked%' OR name IN ('trg_avelo_voucher_date_in_fy_update', 'trg_avelo_accounts_locked_opening_insert', 'trg_avelo_accounts_locked_opening_update') ORDER BY name"
        ) { $0.text(0) }

        XCTAssertTrue(triggerNames.contains("trg_avelo_voucher_date_in_fy_update"))
        XCTAssertTrue(triggerNames.contains("trg_avelo_stock_movements_fy_locked_insert"))
        XCTAssertTrue(triggerNames.contains("trg_avelo_payroll_entries_fy_locked_insert"))
        XCTAssertTrue(triggerNames.contains("trg_avelo_bank_statement_lines_fy_locked_insert"))
        XCTAssertTrue(triggerNames.contains("trg_avelo_bank_reconciliations_fy_locked_insert"))
        XCTAssertTrue(triggerNames.contains("trg_avelo_accounts_locked_opening_update"))
    }

    func testMigrationV012AddsAuditSequenceIndex() throws {
        let db = try migratedDB()
        let indexNames = try db.query(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'avelo_audit_events' ORDER BY name"
        ) { $0.text(0) }
        XCTAssertTrue(indexNames.contains("idx_avelo_audit_sequence"), "Missing idx_avelo_audit_sequence in \(indexNames)")
    }

    func testMigrationV013RepairsLegacyPayrollBankAccountColumn() throws {
        let db = try migratedDB()

        try db.execute("ALTER TABLE avelo_payroll_employees RENAME TO avelo_payroll_employees_old;")
        try db.execute(
            """
            CREATE TABLE avelo_payroll_employees (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id),
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                designation TEXT,
                pan TEXT,
                base_salary_paise INTEGER NOT NULL CHECK(base_salary_paise >= 0),
                is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
                joined_on TEXT NOT NULL,
                end_date TEXT,
                created_at TEXT NOT NULL,
                CHECK(length(trim(code)) > 0),
                CHECK(length(trim(name)) > 0),
                CHECK(length(pan) = 10 OR pan IS NULL),
                UNIQUE(company_id, code)
            );
            """
        )
        try db.execute(
            """
            INSERT INTO avelo_payroll_employees
            (id, company_id, code, name, designation, pan, base_salary_paise, is_active, joined_on, end_date, created_at)
            SELECT id, company_id, code, name, designation, pan, base_salary_paise, is_active, joined_on, end_date, created_at
            FROM avelo_payroll_employees_old;
            """
        )
        try db.execute("DROP TABLE avelo_payroll_employees_old;")
        try db.execute("DELETE FROM avelo_migrations WHERE version = 13;")
        try db.setUserVersion(12)

        try MigrationRunner().runMigrations(on: db)

        XCTAssertEqual(try columns("avelo_payroll_employees", in: db).last, "bank_account_id")
    }
}
