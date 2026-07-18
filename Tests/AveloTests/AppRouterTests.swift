import XCTest
@testable import Avelo

@MainActor
final class AppRouterTests: XCTestCase {

    private final class DirtyProvider: RouterDirtyStateProviding {
        var hasUnsavedChanges = true
        private(set) var discardCount = 0

        func discardUnsavedChanges() {
            discardCount += 1
            hasUnsavedChanges = false
        }
    }

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

    func testKeepEditingPreservesRouteStackAndProvider() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.dirtyStateProvider = provider
        router.pushBrowseReturnContext(.init(companyId: UUID(), financialYearId: nil,
                                             surface: .report(.trialBalance), dataRevision: 0))

        router.go(.reports)
        router.keepEditing()

        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.browseReturnStack.count, 1)
        XCTAssertTrue(router.dirtyStateProvider === provider)
        XCTAssertEqual(provider.discardCount, 0)
    }

    func testDiscardAppliesPendingGoPresentAndResetExactlyOnce() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.dirtyStateProvider = provider

        router.go(.reports)
        router.discardAndContinueNavigation()
        XCTAssertEqual(router.selection, .reports)
        XCTAssertEqual(provider.discardCount, 1)

        provider.hasUnsavedChanges = true
        router.present(.newVoucher)
        router.discardAndContinueNavigation()
        guard case .newVoucher? = router.presentedSheet else {
            return XCTFail("Expected the pending presentation to open the new voucher sheet")
        }
        XCTAssertEqual(provider.discardCount, 2)

        provider.hasUnsavedChanges = true
        router.pushBrowseReturnContext(.init(companyId: UUID(), financialYearId: nil,
                                             surface: .report(.trialBalance), dataRevision: 0))
        router.reset()
        router.discardAndContinueNavigation()
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertNil(router.presentedSheet)
        XCTAssertTrue(router.browseReturnStack.isEmpty)
        XCTAssertEqual(provider.discardCount, 3)
    }

    func testSecondNavigationDoesNotReplacePendingAction() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.dirtyStateProvider = provider

        router.go(.reports)
        router.present(.newVoucher)
        router.discardAndContinueNavigation()

        XCTAssertEqual(router.selection, .reports)
        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(provider.discardCount, 1)
    }

    func testDismissSheetUsesDirtyGate() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.presentedSheet = .newVoucher
        router.dirtyStateProvider = provider

        router.dismissPresentedSheet()
        guard case .newVoucher? = router.presentedSheet else {
            return XCTFail("Expected the dirty-gated sheet to remain visible")
        }
        router.discardAndContinueNavigation()

        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(provider.discardCount, 1)
    }

    func testOnlyCurrentProviderCanClearPendingNavigation() {
        let router = AppRouter()
        let current = DirtyProvider()
        let stale = DirtyProvider()
        router.dirtyStateProvider = current
        router.go(.reports)

        router.clearDirtyStateProvider(stale)
        XCTAssertTrue(router.requiresDirtyNavigationDecision)
        XCTAssertTrue(router.dirtyStateProvider === current)

        router.clearDirtyStateProvider(current)
        XCTAssertFalse(router.requiresDirtyNavigationDecision)
        XCTAssertNil(router.dirtyStateProvider)
    }
}
