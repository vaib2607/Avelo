import XCTest
@testable import Avelo

final class InventoryFailureModeTests: XCTestCase {

    func testRecordMovementFailsWhenRunningBalanceLookupFails() {
        let db = try! SQLiteDatabase(path: ":memory:")
        let service = InventoryService(db: db, companyId: UUID())

        XCTAssertThrowsError(
            try service.recordMovement(
                itemId: UUID(),
                date: Date(),
                type: .stockIn,
                quantity: 1,
                ratePaise: 100
            )
        )
    }
}
