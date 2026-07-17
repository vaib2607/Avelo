import XCTest
@testable import Avelo

final class InventoryLinkModeTests: XCTestCase {

    func testOnlyManualInventoryLinkModeIsAvailableForProduction() {
        XCTAssertTrue(InventoryLinkMode.manual.isAvailableForProduction)
        XCTAssertFalse(InventoryLinkMode.autoPrompt.isAvailableForProduction)
        XCTAssertFalse(InventoryLinkMode.autoSilent.isAvailableForProduction)
    }

    func testCompanyServiceRejectsUnsupportedAutomaticInventoryModes() throws {
        let tc = try TestCompany.make()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DatabaseManager(
            appSupportDirectory: root,
            keyStore: InMemoryCompanyKeyStore()
        )
        let service = CompanyService(db: tc.db, companyId: tc.companyId, manager: manager)

        for mode in [InventoryLinkMode.autoPrompt, .autoSilent] {
            XCTAssertThrowsError(
                try service.setInventoryMode(enabled: true, linkMode: mode)
            ) { error in
                guard case .businessRule(let message) = AppError.wrap(error) else {
                    return XCTFail("Expected unsupported link mode to fail as a business rule, got \(error)")
                }
                XCTAssertTrue(message.localizedCaseInsensitiveContains("not available"))
            }
        }
    }

    func testGeneralCompanyUpdateCannotBypassAutomaticModePolicy() throws {
        let tc = try TestCompany.make()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CompanyService(
            db: tc.db,
            companyId: tc.companyId,
            manager: try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        )
        var company = try XCTUnwrap(service.current())
        company.inventoryLinkMode = .autoSilent

        XCTAssertThrowsError(try service.update(company))
        XCTAssertEqual(try service.current()?.inventoryLinkMode, .manual)
        XCTAssertEqual(
            try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .companyUpdated)).count,
            0
        )
    }

    func testLegacyAutomaticModesNeverCreateHiddenStockConsequences() throws {
        for mode in [InventoryLinkMode.autoPrompt, .autoSilent] {
            let tc = try TestCompany.make()
            try tc.db.execute(
                "UPDATE avelo_companies SET inventory_link_mode = ? WHERE id = ?",
                [.text(mode.rawValue), .text(tc.companyId.uuidString)]
            )
            let service = VoucherService(db: tc.db, companyId: tc.companyId)
            let first = try service.post(
                draft: tc.draft(type: .sales, on: "2024-06-01", lines: [
                    tc.line(tc.cashId, 1_000, .debit),
                    tc.line(tc.salesId, 1_000, .credit)
                ]),
                in: tc.fy
            )
            XCTAssertNil(first.inventoryPrompt, "\(mode)")
            _ = try service.edit(
                first.voucher.id,
                with: tc.draft(type: .sales, on: "2024-06-02", lines: [
                    tc.line(tc.cashId, 1_000, .debit),
                    tc.line(tc.salesId, 1_000, .credit)
                ]),
                in: tc.fy
            )
            _ = try service.cancel(first.voucher.id, reason: "legacy mode matrix")

            let second = try service.post(
                draft: tc.draft(type: .sales, on: "2024-06-03", lines: [
                    tc.line(tc.cashId, 2_000, .debit),
                    tc.line(tc.salesId, 2_000, .credit)
                ]),
                in: tc.fy
            )
            _ = try service.reverse(second.voucher.id, reason: "legacy mode matrix")

            let movementCount = try tc.db.queryOne(
                "SELECT COUNT(*) FROM avelo_stock_movements WHERE company_id = ?",
                bind: [.text(tc.companyId.uuidString)]
            ) { $0.int(0) } ?? 0
            XCTAssertEqual(movementCount, 0, "\(mode) created a hidden stock movement")
        }
    }
}
