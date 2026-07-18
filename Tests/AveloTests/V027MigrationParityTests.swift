import XCTest
@testable import Avelo

final class V027MigrationParityTests: XCTestCase {
    func testPopulatedV026UpgradeBackfillsCanonicalTracksLosslessly() throws {
        let db = try v26Database()
        let fixture = try TestCompany.seed(into: db, companyId: UUID(), companyName: "V26")
        let voucherId = UUID()
        let itemId = UUID()
        let now = Date()
        try db.execute("INSERT INTO avelo_inventory_items (id, company_id, code, name, unit, valuation_method, is_active, created_at) VALUES (?, ?, 'V26-I', 'Legacy item', 'NOS', 'fifo', 1, ?)", [.text(itemId.uuidString), .text(fixture.companyId.uuidString), .timestamp(now)])
        try db.execute("INSERT INTO avelo_vouchers (id, company_id, financial_year_id, voucher_type_code, number, date, narration, total_paise, created_at, updated_at) VALUES (?, ?, ?, 'Journal', 'V26-1', ?, 'legacy', 100, ?, ?)", [.text(voucherId.uuidString), .text(fixture.companyId.uuidString), .text(fixture.fy.id.uuidString), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(now), .timestamp(now)])
        for (id, account, side, order) in [(UUID(), fixture.cashId, "debit", 0), (UUID(), fixture.salesId, "credit", 1)] {
            try db.execute("INSERT INTO avelo_ledger_lines (id, company_id, voucher_id, account_id, amount_paise, side, line_order) VALUES (?, ?, ?, ?, 100, ?, ?)", [.text(id.uuidString), .text(fixture.companyId.uuidString), .text(voucherId.uuidString), .text(account.uuidString), .text(side), .integer(Int64(order))])
        }
        let movementId = UUID()
        try db.execute("INSERT INTO avelo_stock_movements (id, company_id, item_id, voucher_id, date, movement_type, quantity, unit_cost_paise, total_value_paise, created_at) VALUES (?, ?, ?, ?, ?, 'in', 2, 50, 100, ?)", [.text(movementId.uuidString), .text(fixture.companyId.uuidString), .text(itemId.uuidString), .text(voucherId.uuidString), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(now)])

        try MigrationRunner().runMigrations(on: db)
        XCTAssertEqual(try db.userVersion(), SchemaVersion.current.rawValue)
        XCTAssertEqual(try db.queryOne("SELECT COUNT(*) FROM trn_accounting WHERE voucher_id = ?", bind: [.text(voucherId.uuidString)]) { $0.int(0) }, 2)
        XCTAssertEqual(try db.queryOne("SELECT quantity_numerator FROM trn_inventory WHERE id = ?", bind: [.text(movementId.uuidString)]) { $0.int(0) }, 2)
        XCTAssertEqual(try db.queryOne("SELECT quantity_denominator FROM trn_inventory WHERE id = ?", bind: [.text(movementId.uuidString)]) { $0.int(0) }, 1)
        XCTAssertEqual(try db.queryOne("SELECT landed_cost_paise FROM trn_inventory WHERE id = ?", bind: [.text(movementId.uuidString)]) { $0.int(0) }, 0)
        XCTAssertEqual(try db.queryOne("SELECT COUNT(*) FROM avelo_inventory_locations WHERE company_id = ? AND code = 'MAIN'", bind: [.text(fixture.companyId.uuidString)]) { $0.int(0) }, 1)
    }

    func testUnbalancedV026BackfillFailsClosedAtV026() throws {
        let db = try v26Database()
        let fixture = try TestCompany.seed(into: db, companyId: UUID(), companyName: "Bad V26")
        let voucherId = UUID()
        let now = Date()
        try db.execute("INSERT INTO avelo_vouchers (id, company_id, financial_year_id, voucher_type_code, number, date, narration, total_paise, created_at, updated_at) VALUES (?, ?, ?, 'Journal', 'BAD', ?, 'bad', 100, ?, ?)", [.text(voucherId.uuidString), .text(fixture.companyId.uuidString), .text(fixture.fy.id.uuidString), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(now), .timestamp(now)])
        try db.execute("INSERT INTO avelo_ledger_lines (id, company_id, voucher_id, account_id, amount_paise, side, line_order) VALUES (?, ?, ?, ?, 100, 'debit', 0)", [.text(UUID().uuidString), .text(fixture.companyId.uuidString), .text(voucherId.uuidString), .text(fixture.cashId.uuidString)])
        XCTAssertThrowsError(try MigrationRunner().runMigrations(on: db))
        XCTAssertEqual(try db.userVersion(), 26)
        XCTAssertEqual(try db.queryOne("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'trn_accounting'") { $0.int(0) }, 0)
    }

    func testMalformedV026IdentifierFailsClosedAtV026() throws {
        let db = try v26Database()
        let fixture = try TestCompany.seed(into: db, companyId: UUID(), companyName: "Malformed V26")
        let voucherId = UUID()
        let now = Date()
        try db.execute("INSERT INTO avelo_vouchers (id, company_id, financial_year_id, voucher_type_code, number, date, narration, total_paise, created_at, updated_at) VALUES (?, ?, ?, 'Journal', 'BAD-ID', ?, 'bad', 100, ?, ?)", [.text(voucherId.uuidString), .text(fixture.companyId.uuidString), .text(fixture.fy.id.uuidString), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(now), .timestamp(now)])
        try db.execute("INSERT INTO avelo_ledger_lines (id, company_id, voucher_id, account_id, amount_paise, side, line_order) VALUES ('not-a-uuid', ?, ?, ?, 100, 'debit', 0)", [.text(fixture.companyId.uuidString), .text(voucherId.uuidString), .text(fixture.cashId.uuidString)])
        try db.execute("INSERT INTO avelo_ledger_lines (id, company_id, voucher_id, account_id, amount_paise, side, line_order) VALUES (?, ?, ?, ?, 100, 'credit', 1)", [.text(UUID().uuidString), .text(fixture.companyId.uuidString), .text(voucherId.uuidString), .text(fixture.salesId.uuidString)])

        XCTAssertThrowsError(try MigrationRunner().runMigrations(on: db))
        XCTAssertEqual(try db.userVersion(), 26)
        XCTAssertEqual(try db.queryOne("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'trn_accounting'") { $0.int(0) }, 0)
    }

    private func v26Database() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner(migrations: MigrationRunner.defaultMigrations.filter { $0.version.rawValue <= 26 }).runMigrations(on: db)
        return db
    }
}
