import XCTest
@testable import Avelo

final class AppActionRegistryTests: XCTestCase {

    private func voucher(type: VoucherType.Code, isReversal: Bool = false) -> Voucher {
        Voucher(
            companyId: UUID(),
            financialYearId: UUID(),
            voucherTypeCode: type,
            number: "1",
            date: Date(),
            isReversal: isReversal
        )
    }

    // MARK: - Accounts

    func testAccountAlterAndDrillDownRequireASelectedAccount() {
        let empty = AppActionContext()
        XCTAssertFalse(AppActionRegistry.availability(for: .accountAlter, in: empty).isAvailable)
        XCTAssertFalse(AppActionRegistry.availability(for: .accountDrillDown, in: empty).isAvailable)

        let withAccount = AppActionContext(accountId: UUID())
        XCTAssertTrue(AppActionRegistry.availability(for: .accountAlter, in: withAccount).isAvailable)
        XCTAssertTrue(AppActionRegistry.availability(for: .accountDrillDown, in: withAccount).isAvailable)
    }

    func testAccountCreateAndAccountsDisplayAreAlwaysAvailable() {
        let context = AppActionContext()
        XCTAssertTrue(AppActionRegistry.availability(for: .accountCreate, in: context).isAvailable)
        XCTAssertTrue(AppActionRegistry.availability(for: .accountsDisplay, in: context).isAvailable)
    }

    // MARK: - Vouchers

    func testVoucherAlterAndReverseAreUnavailableForReversalVouchers() {
        let normal = AppActionContext(voucher: voucher(type: .payment, isReversal: false))
        XCTAssertTrue(AppActionRegistry.availability(for: .voucherAlter, in: normal).isAvailable)
        XCTAssertTrue(AppActionRegistry.availability(for: .voucherReverse, in: normal).isAvailable)

        let reversal = AppActionContext(voucher: voucher(type: .payment, isReversal: true))
        let alterAvailability = AppActionRegistry.availability(for: .voucherAlter, in: reversal)
        let reverseAvailability = AppActionRegistry.availability(for: .voucherReverse, in: reversal)
        XCTAssertFalse(alterAvailability.isAvailable)
        XCTAssertFalse(reverseAvailability.isAvailable)
        XCTAssertNotNil(alterAvailability.rejectionReason)
        XCTAssertNotNil(reverseAvailability.rejectionReason)
    }

    func testVoucherAlterAndReverseRequireASelectedVoucher() {
        let empty = AppActionContext()
        XCTAssertFalse(AppActionRegistry.availability(for: .voucherAlter, in: empty).isAvailable)
        XCTAssertFalse(AppActionRegistry.availability(for: .voucherReverse, in: empty).isAvailable)
    }

    func testVoucherDuplicateOnlyAvailableForTypesWithACreationSheet() {
        let creatable = AppActionContext(voucher: voucher(type: .sales))
        XCTAssertTrue(AppActionRegistry.availability(for: .voucherDuplicate, in: creatable).isAvailable)

        // .opening/.payroll are system-generated with no "New X" sheet to
        // duplicate into (mirrors VouchersView's original routerSheet(for:) gate).
        let systemGenerated = AppActionContext(voucher: voucher(type: .opening))
        XCTAssertFalse(AppActionRegistry.availability(for: .voucherDuplicate, in: systemGenerated).isAvailable)
    }

    func testVoucherExportPDFOnlyAvailableForSalesAndPurchase() {
        XCTAssertTrue(AppActionRegistry.availability(for: .voucherExportPDF, in: AppActionContext(voucher: voucher(type: .sales))).isAvailable)
        XCTAssertTrue(AppActionRegistry.availability(for: .voucherExportPDF, in: AppActionContext(voucher: voucher(type: .purchase))).isAvailable)
        XCTAssertFalse(AppActionRegistry.availability(for: .voucherExportPDF, in: AppActionContext(voucher: voucher(type: .journal))).isAvailable)
    }

    func testAllEightCreatableVoucherTypesAreRegistered() {
        let creatable: [VoucherType.Code] = [.journal, .payment, .receipt, .contra, .purchase, .sales, .creditNote, .debitNote]
        for type in creatable {
            XCTAssertNotNil(AppActionRegistry.action(for: .voucherCreate(type)), "missing registry entry for \(type)")
        }
    }

    // MARK: - Trial Balance / Day Book

    func testTrialBalanceAndDayBookDisplayAreAlwaysAvailable() {
        let context = AppActionContext()
        XCTAssertTrue(AppActionRegistry.availability(for: .trialBalanceDisplay, in: context).isAvailable)
        XCTAssertTrue(AppActionRegistry.availability(for: .dayBookDisplay, in: context).isAvailable)
    }

    // MARK: - Direct invocation of an unavailable action

    /// Mirrors `AccountEligibilityPolicyTests`' pattern of testing the policy
    /// function directly. Proves an unavailable action can't be invoked by
    /// calling `perform` straight through the registry — not merely by
    /// checking that a UI button *would* be disabled.
    @MainActor
    func testUnavailableActionCannotBeInvokedViaDirectPerform() {
        let router = AppRouter()
        let reversalVoucher = voucher(type: .payment, isReversal: true)
        let context = AppActionContext(voucher: reversalVoucher)

        let result = AppActionRegistry.perform(.voucherAlter, context: context, router: router)

        XCTAssertFalse(result.succeeded)
        XCTAssertNotNil(result.rejectionReason)
        // The router must not have been told to present the edit sheet.
        XCTAssertNil(router.presentedSheet)
    }

    @MainActor
    func testUnavailableAccountAlterCannotOpenASheetEvenWithoutASelection() {
        let router = AppRouter()
        let result = AppActionRegistry.perform(.accountAlter, router: router)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(router.presentedSheet)
    }

    @MainActor
    func testAvailableActionAppliesItsEffectThroughTheRouter() {
        let router = AppRouter()
        let context = AppActionContext(voucher: voucher(type: .payment, isReversal: false))

        let result = AppActionRegistry.perform(.accountCreate, context: context, router: router)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(router.presentedSheet?.id, RouterSheet.newAccount.id)
    }
}
