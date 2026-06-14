import XCTest
@testable import Avelo

final class MasterDataTests: XCTestCase {
    func testCostCentreAndBudgetAreDeferredByFrozenSchema() throws {
        let tc = try TestCompany.make()
        let repo = MasterDataRepository(db: tc.db)
        let centre = CostCentre(companyId: tc.companyId, code: "CC-001", name: "Main Shop")
        let budget = Budget(companyId: tc.companyId, financialYearId: tc.fy.id, costCentreId: centre.id, code: "B-001", name: "Marketing", plannedPaise: 250000)

        XCTAssertThrowsError(try repo.insert(centre)) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }
        XCTAssertThrowsError(try repo.insert(budget)) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }
    }

    func testInventoryItemMasterFrozenFieldsRoundTrip() throws {
        let tc = try TestCompany.make()
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try svc.createItem(code: "ITEMX", name: "Item X", unit: "PCS", valuationMethod: .weightedAverage)
        var loaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(loaded.valuationMethod, .weightedAverage)
        loaded.name = "Item X2"
        loaded.isActive = false
        try InventoryRepository(db: tc.db).updateItem(loaded)
        let reloaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(reloaded.name, "Item X2")
        XCTAssertFalse(reloaded.isActive)
    }
}
