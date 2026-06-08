import XCTest
@testable import Avelo

@MainActor
final class KeyboardBridgeTests: XCTestCase {

    func testDispatchRoutesPromotedNavigationCommands() {
        let router = AppRouter()
        let bridge = KeyboardBridge()
        bridge.attach(router: router)

        bridge.dispatch(.openInventory)
        XCTAssertEqual(router.selection, .inventory)

        bridge.dispatch(.openPayroll)
        XCTAssertEqual(router.selection, .payroll)

        bridge.dispatch(.openBanking)
        XCTAssertEqual(router.selection, .banking)
    }

    func testDispatchRoutesExistingShellCommands() {
        let router = AppRouter()
        let bridge = KeyboardBridge()
        bridge.attach(router: router)

        bridge.dispatch(.openAudit)
        XCTAssertEqual(router.selection, .audit)

        bridge.dispatch(.openSettings)
        XCTAssertEqual(router.selection, .settings)
    }
}
