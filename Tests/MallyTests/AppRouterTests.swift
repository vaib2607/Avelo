import XCTest
@testable import Mally

@MainActor
final class AppRouterTests: XCTestCase {

    func testOpenLedgerPointsReportsToRequestedAccount() {
        let router = AppRouter()
        let accountId = UUID()

        router.openLedger(accountId)

        XCTAssertEqual(router.selection, .reports)
        XCTAssertEqual(router.pendingLedgerAccountId, accountId)
    }

    func testResetClearsDeepLinkStateAndReturnsToDashboard() {
        let router = AppRouter()
        let accountId = UUID()

        router.openLedger(accountId)
        router.present(.newVoucher)
        router.alert(.init(title: "Alert", message: "Message"))
        router.reset()

        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertNil(router.pendingLedgerAccountId)
        XCTAssertNil(router.presentedSheet)
        XCTAssertNil(router.presentedAlert)
    }
}
