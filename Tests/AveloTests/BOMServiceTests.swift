import XCTest
@testable import Avelo

final class BOMServiceTests: XCTestCase {
    func testBomRoundTrip() throws {
        let tc = try TestCompany.make()
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)
        let assembly = try svc.createItem(code: "ASM001", name: "Assembled Item", unit: "NOS", openingQuantity: 0, openingRatePaise: 0)
        let comp1 = try svc.createItem(code: "CMP001", name: "Component A", unit: "NOS", openingQuantity: 0, openingRatePaise: 0)
        let comp2 = try svc.createItem(code: "CMP002", name: "Component B", unit: "NOS", openingQuantity: 0, openingRatePaise: 0)

        try BOMService(db: tc.db, companyId: tc.companyId).saveBOM(
            assemblyItemId: assembly.id,
            outputQuantity: 2,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: comp1.id, quantity: 3),
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: comp2.id, quantity: 1.5)
            ]
        )

        let loaded = try XCTUnwrap(BOMService(db: tc.db, companyId: tc.companyId).loadBOM(for: assembly.id))
        XCTAssertEqual(loaded.0.assemblyItemId, assembly.id)
        XCTAssertEqual(loaded.0.outputQuantity, 2)
        XCTAssertEqual(loaded.1.count, 2)
        XCTAssertEqual(loaded.1[0].componentItemId, comp1.id)
        XCTAssertEqual(loaded.1[1].componentItemId, comp2.id)
    }
}
