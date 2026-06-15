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
            "avelo_companies",
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
            "created_at"
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
            "created_at"
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
    }
}
