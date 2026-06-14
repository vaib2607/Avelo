import XCTest
@testable import Avelo

final class DemoCompanySeederTests: XCTestCase {

    func testDemoCompanySeederCreatesRichDemoData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
        let entry = try await DemoCompanySeeder.ensureDemoCompany(manager: manager)
        let dbURL = try await manager.companyFileURL(id: entry.id)
        let db = try SQLiteDatabase(path: dbURL.path)
        defer { db.close() }

        let company = try XCTUnwrap(CompanyRepository(db: db).findById(entry.id))
        XCTAssertEqual(company.name, DemoCompanySeeder.companyDisplayName)

        let fy = try XCTUnwrap(FinancialYearRepository(db: db).findMostRecent(entry.id))
        let accountCount = try db.queryOne("SELECT COUNT(*) FROM avelo_accounts WHERE company_id = ?", bind: [.text(entry.id.uuidString)]) { $0.int(0) } ?? 0
        let voucherCount = try db.queryOne("SELECT COUNT(*) FROM avelo_vouchers WHERE company_id = ?", bind: [.text(entry.id.uuidString)]) { $0.int(0) } ?? 0
        let itemCount = try db.queryOne("SELECT COUNT(*) FROM avelo_inventory_items WHERE company_id = ?", bind: [.text(entry.id.uuidString)]) { $0.int(0) } ?? 0
        let employeeCount = try db.queryOne("SELECT COUNT(*) FROM avelo_payroll_employees WHERE company_id = ?", bind: [.text(entry.id.uuidString)]) { $0.int(0) } ?? 0
        let bankReconciliationCount = try db.queryOne("SELECT COUNT(*) FROM avelo_bank_reconciliations WHERE company_id = ?", bind: [.text(entry.id.uuidString)]) { $0.int(0) } ?? 0
        let auditCount = try AuditRepository(db: db).list(filter: .init(companyId: entry.id)).count

        XCTAssertGreaterThanOrEqual(accountCount, 14)
        XCTAssertGreaterThanOrEqual(voucherCount, 6)
        XCTAssertGreaterThanOrEqual(itemCount, 2)
        XCTAssertGreaterThanOrEqual(employeeCount, 2)
        XCTAssertGreaterThanOrEqual(bankReconciliationCount, 2)
        XCTAssertGreaterThan(auditCount, 0)

        let reportService = ReportService(db: db, companyId: entry.id)
        let trialBalance = try reportService.trialBalance(asOfDate: fy.endDate, financialYearId: fy.id)
        XCTAssertFalse(trialBalance.rows.isEmpty)
    }
}
