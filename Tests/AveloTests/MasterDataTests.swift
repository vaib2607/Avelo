import XCTest
@testable import Avelo

final class MasterDataTests: XCTestCase {
<<<<<<< HEAD
    func testCostCentreAndBudgetAreDeferredByFrozenSchema() throws {
=======
    func testCostCentreAndBudgetRoundTrip() throws {
>>>>>>> origin/main
        let tc = try TestCompany.make()
        let repo = MasterDataRepository(db: tc.db)
        let centre = CostCentre(companyId: tc.companyId, code: "CC-001", name: "Main Shop")
        let budget = Budget(companyId: tc.companyId, financialYearId: tc.fy.id, costCentreId: centre.id, code: "B-001", name: "Marketing", plannedPaise: 250000)

<<<<<<< HEAD
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
=======
        try repo.insert(centre)
        try repo.insert(budget)

        let centres = try repo.listCostCentres(companyId: tc.companyId)
        XCTAssertEqual(centres.count, 1)
        XCTAssertEqual(centres.first?.name, "Main Shop")
    }

    func testInventoryItemMasterExtensionsRoundTrip() throws {
        let tc = try TestCompany.make()
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try svc.createItem(code: "ITEMX", name: "Item X", unit: "PCS", openingQuantity: 1, openingRatePaise: 1000,
                                      stockGroup: "G1", stockCategory: "C1", godown: "D1", barcode: "BC1", hsnSac: "1001")
        var loaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(loaded.stockGroup, "G1")
        XCTAssertEqual(loaded.stockCategory, "C1")
        XCTAssertEqual(loaded.godown, "D1")
        XCTAssertEqual(loaded.barcode, "BC1")
        XCTAssertEqual(loaded.hsnSac, "1001")
        loaded.alternateUnit = "BOX"
        loaded.reorderLevel = 10
        loaded.priceLevel1Paise = 1100
        loaded.priceLevel2Paise = 1200
        try InventoryRepository(db: tc.db).updateItem(loaded)
        let reloaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(reloaded.alternateUnit, "BOX")
        XCTAssertEqual(reloaded.reorderLevel, 10)
        XCTAssertEqual(reloaded.priceLevel1Paise, 1100)
        XCTAssertEqual(reloaded.priceLevel2Paise, 1200)
>>>>>>> origin/main
    }
}
