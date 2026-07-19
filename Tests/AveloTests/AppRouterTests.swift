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

    func testDeepLinksRespectDirtyNavigationAndApplyOnlyAfterDiscard() {
        let router = AppRouter()
        let provider = DirtyProvider()
        let accountId = UUID()
        router.dirtyStateProvider = provider

        router.openLedger(accountId)

        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertNil(router.pendingLedgerAccountId)
        XCTAssertTrue(router.requiresDirtyNavigationDecision)

        router.discardAndContinueNavigation()

        XCTAssertEqual(router.selection, .reports)
        XCTAssertEqual(router.pendingLedgerAccountId, accountId)
        XCTAssertEqual(provider.discardCount, 1)
    }

    func testCapabilityEvictionUsesDirtyNavigationBeforeDismissingSheet() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.setInventoryEnabled(true)
        router.selection = .inventory
        router.presentedSheet = .newItem
        router.dirtyStateProvider = provider

        router.setInventoryEnabled(false)

        guard case .newItem? = router.presentedSheet else {
            return XCTFail("Dirty editor must remain visible until discard")
        }
        XCTAssertEqual(router.selection, .inventory, "route eviction must wait for the dirty decision too")
        XCTAssertTrue(router.requiresDirtyNavigationDecision)

        router.discardAndContinueNavigation()
        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(provider.discardCount, 1)
    }

    func testSuccessfulVoucherSubmissionClearsOnlyItsProviderAndDismissesSheet() {
        let router = AppRouter()
        let provider = DirtyProvider()
        router.presentedSheet = .newVoucher
        router.dirtyStateProvider = provider

        router.completeVoucherSubmission(provider)

        XCTAssertNil(router.presentedSheet)
        XCTAssertNil(router.dirtyStateProvider)
        XCTAssertFalse(router.requiresDirtyNavigationDecision)
        XCTAssertEqual(provider.discardCount, 0)
    }

    func testExternalContextChangeWaitsForDirtyDiscard() {
        let router = AppRouter()
        let provider = DirtyProvider()
        var applied = false
        router.dirtyStateProvider = provider

        router.requestExternalContextChange { applied = true }

        XCTAssertFalse(applied)
        XCTAssertTrue(router.requiresDirtyNavigationDecision)
        router.discardAndContinueNavigation()
        XCTAssertTrue(applied)
        XCTAssertEqual(provider.discardCount, 1)
    }

    /// `NewVoucherSheet` presents its nested `NewAccountSheet` through its own
    /// isolated `AppRouter` instance specifically so a dirty voucher editor's
    /// pending navigation can never be observed or cleared by that nested
    /// sheet's lifecycle. This proves the isolation holds both ways.
    func testNestedAccountCreationRouterCannotObserveOrClearParentPendingNavigation() {
        let parentRouter = AppRouter()
        let voucherProvider = DirtyProvider()
        parentRouter.dirtyStateProvider = voucherProvider
        parentRouter.go(.reports)
        XCTAssertTrue(parentRouter.requiresDirtyNavigationDecision)

        let nestedRouter = AppRouter()
        nestedRouter.present(.newAccount)
        XCTAssertEqual(nestedRouter.presentedSheet?.id, RouterSheet.newAccount.id)
        nestedRouter.dismissPresentedSheet()
        XCTAssertNil(nestedRouter.presentedSheet)

        XCTAssertTrue(parentRouter.requiresDirtyNavigationDecision)
        XCTAssertEqual(parentRouter.selection, .dashboard)
        XCTAssertEqual(voucherProvider.discardCount, 0)
    }
}
