import XCTest
@testable import Avelo

@MainActor
final class KeyboardBridgeTests: XCTestCase {

    func testDispatchRoutesPromotedNavigationCommands() {
        let router = AppRouter()
        let bridge = KeyboardBridge()
        bridge.attach(router: router)
<<<<<<< HEAD
        bridge.attach(isInventoryEnabled: { true })
=======
>>>>>>> origin/main

        bridge.dispatch(.openInventory)
        XCTAssertEqual(router.selection, .inventory)

<<<<<<< HEAD
        bridge.dispatch(.openGST)
        XCTAssertEqual(router.selection, .gst)

=======
>>>>>>> origin/main
        bridge.dispatch(.openPayroll)
        XCTAssertEqual(router.selection, .payroll)

        bridge.dispatch(.openBanking)
        XCTAssertEqual(router.selection, .banking)
    }

<<<<<<< HEAD
    // AVL-P0-033: inventory keyboard shortcuts must no-op, not route to a
    // screen that no longer appears anywhere else, when the company has
    // inventory disabled.
    func testDispatchSuppressesInventoryCommandsWhenDisabled() {
        let router = AppRouter()
        let bridge = KeyboardBridge()
        bridge.attach(router: router)
        bridge.attach(isInventoryEnabled: { false })

        bridge.dispatch(.openInventory)
        XCTAssertEqual(router.selection, .dashboard)

        bridge.dispatch(.newItem)
        XCTAssertNil(router.presentedSheet)
    }

=======
>>>>>>> origin/main
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
