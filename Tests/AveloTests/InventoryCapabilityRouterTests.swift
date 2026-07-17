import XCTest
@testable import Avelo

@MainActor
final class InventoryCapabilityRouterTests: XCTestCase {
    func testDisabledCapabilityRejectsDirectInventoryRoutes() {
        let router = AppRouter()

        router.go(.inventory)
        router.openReport(.stockValuation)
        router.present(.newItem)

        router.selection = .inventory
        router.pendingReportSelection = .stockAgeing
        router.presentedSheet = .newItem

        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertNil(router.pendingReportSelection)
        XCTAssertNil(router.presentedSheet)
    }

    func testEnablingCapabilityAuthorizesInventoryRoutes() {
        let router = AppRouter()
        router.setInventoryEnabled(true)

        router.go(.inventory)
        XCTAssertEqual(router.selection, .inventory)
        router.openReport(.stockMovement)
        XCTAssertEqual(router.selection, .reports)
        XCTAssertEqual(router.pendingReportSelection, .stockMovement)
        router.present(.newItem)
        XCTAssertEqual(router.presentedSheet?.id, RouterSheet.newItem.id)
    }

    func testDisablingCapabilityInvalidatesStaleInventoryState() {
        let router = AppRouter()
        router.setInventoryEnabled(true)
        router.go(.inventory)
        router.openReport(.stockAgeing)
        router.present(.newItem)

        router.setInventoryEnabled(false)

        XCTAssertEqual(router.selection, .reports)
        XCTAssertNil(router.pendingReportSelection)
        XCTAssertNil(router.presentedSheet)
    }
}
