import XCTest
@testable import Avelo

final class BOMServiceTests: XCTestCase {
    func testSaveAndLoadBomRoundTripsPersistedComponents() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)

        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let componentA = try inventory.createItem(code: "RM-001", name: "Raw A", unit: "PCS")
        let componentB = try inventory.createItem(code: "RM-002", name: "Raw B", unit: "PCS")

        try bomService.saveBOM(
            assemblyItemId: assembly.id,
            outputQuantity: 2,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: componentA.id, quantity: 3),
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: componentB.id, quantity: 1.5)
            ]
        )

        let loaded = try XCTUnwrap(bomService.loadBOM(for: assembly.id))
        XCTAssertEqual(loaded.0.assemblyItemId, assembly.id)
        XCTAssertEqual(loaded.0.outputQuantity, 2, accuracy: 0.000001)
        XCTAssertEqual(loaded.1.count, 2)
        XCTAssertEqual(loaded.1[0].componentItemId, componentA.id)
        XCTAssertEqual(loaded.1[0].quantity, 3, accuracy: 0.000001)
        XCTAssertEqual(loaded.1[0].lineOrder, 0)
        XCTAssertEqual(loaded.1[1].componentItemId, componentB.id)
        XCTAssertEqual(loaded.1[1].quantity, 1.5, accuracy: 0.000001)
        XCTAssertEqual(loaded.1[1].lineOrder, 1)
    }

    func testSaveBomRejectsDirectCycle() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")

        XCTAssertThrowsError(
            try bomService.saveBOM(
                assemblyItemId: assembly.id,
                outputQuantity: 1,
                components: [
                    BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: assembly.id, quantity: 1)
                ]
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected businessRule, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("circular bom"))
        }
    }

    func testSaveBomRejectsIndirectCycle() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)

        let itemA = try inventory.createItem(code: "ASM-A", name: "Assembly A", unit: "PCS")
        let itemB = try inventory.createItem(code: "ASM-B", name: "Assembly B", unit: "PCS")
        let itemC = try inventory.createItem(code: "ASM-C", name: "Assembly C", unit: "PCS")
        let raw = try inventory.createItem(code: "RM-001", name: "Raw", unit: "PCS")

        try bomService.saveBOM(
            assemblyItemId: itemB.id,
            outputQuantity: 1,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: itemC.id, quantity: 1),
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: raw.id, quantity: 2)
            ]
        )
        try bomService.saveBOM(
            assemblyItemId: itemC.id,
            outputQuantity: 1,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: raw.id, quantity: 1)
            ]
        )

        try bomService.saveBOM(
            assemblyItemId: itemA.id,
            outputQuantity: 1,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: itemB.id, quantity: 1)
            ]
        )

        XCTAssertThrowsError(
            try bomService.saveBOM(
                assemblyItemId: itemC.id,
                outputQuantity: 1,
                components: [
                    BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: itemA.id, quantity: 1)
                ]
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected businessRule, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("circular bom"))
        }
    }
}
