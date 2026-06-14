import XCTest
@testable import Avelo

final class BOMServiceTests: XCTestCase {
    func testBomIsDeferredByFrozenSchema() throws {
        let tc = try TestCompany.make()
        let assemblyId = UUID()
        let componentId = UUID()

        XCTAssertThrowsError(try BOMService(db: tc.db, companyId: tc.companyId).saveBOM(
            assemblyItemId: assemblyId,
            outputQuantity: 2,
            components: [
                BOMComponent(companyId: tc.companyId, bomId: UUID(), componentItemId: componentId, quantity: 3)
            ]
        )) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }
    }
}
