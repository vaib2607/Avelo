import XCTest
@testable import Avelo

@MainActor
final class ReportsViewModelTests: XCTestCase {

    func testLedgerSelectionLoadsRequestedAccountLedger() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.ledgerAccountId = tc.cashId
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.reload()

        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)
        XCTAssertEqual(vm.ledger?.accountName, "Cash")
        XCTAssertEqual(vm.ledger?.rows.count, 1)
        XCTAssertEqual(vm.ledger?.rows.first?.voucherId, try XCTUnwrap(vm.ledger?.rows.first?.voucherId))
    }

    // AVL-P1-036 (Alt+N comparative columns): the comparative column must
    // reconcile exactly to what the same report returns standalone for that
    // prior period — no separate math, no drift.

    func testComparativeTrialBalanceReconcilesToStandaloneRunForPriorYear() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let asOf = DateFormatters.parseDate("2024-06-01")!
        let priorAsOf = Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: asOf)!

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = asOf
        vm.comparativeEnabled = true
        vm.reload()

        let standalone = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: priorAsOf, financialYearId: tc.fy.id).rows

        XCTAssertEqual(vm.comparativeTrialBalance, standalone)
    }

    func testComparativeDisabledLeavesComparativeTrialBalanceEmpty() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = DateFormatters.parseDate("2024-06-01")!
        vm.reload()

        XCTAssertTrue(vm.comparativeTrialBalance.isEmpty)
    }

    func testComparativeProfitLossReconcilesToStandaloneRunForPriorYear() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let fromDate = DateFormatters.parseDate("2024-06-01")!
        let toDate = DateFormatters.parseDate("2024-06-30")!
        let cal = Calendar(identifier: .gregorian)
        let priorFrom = cal.date(byAdding: .year, value: -1, to: fromDate)!
        let priorTo = cal.date(byAdding: .year, value: -1, to: toDate)!

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .profitLoss
        vm.fromDate = fromDate
        vm.toDate = toDate
        vm.comparativeEnabled = true
        vm.reload()

        let standalone = try ReportService(db: tc.db, companyId: tc.companyId)
            .profitAndLoss(fromDate: priorFrom, toDate: priorTo, financialYearId: tc.fy.id)

        XCTAssertEqual(vm.comparativeProfitLoss, standalone)
    }

    func testComparativeBalanceSheetReconcilesToStandaloneRunForPriorYear() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let asOf = DateFormatters.parseDate("2024-06-01")!
        let priorAsOf = Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: asOf)!

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .balanceSheet
        vm.asOf = asOf
        vm.comparativeEnabled = true
        vm.reload()

        let standalone = try ReportService(db: tc.db, companyId: tc.companyId)
            .balanceSheet(asOfDate: priorAsOf, financialYearId: tc.fy.id)

        XCTAssertEqual(vm.comparativeBalanceSheet, standalone)
    }

    func testLedgerSelectionWithoutAccountClearsLedgerResult() throws {
        let tc = try TestCompany.make()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)

        vm.selection = .ledger
        vm.ledgerAccountId = nil
        vm.reload()

        XCTAssertNil(vm.ledger)
        XCTAssertNil(vm.error)
    }

    func testLedgerSelectionReloadsWhenAccountChanges() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)
        _ = try service.post(draft: tc.draft(on: "2024-06-15", lines: [
            tc.line(tc.rentId, 7000, .debit),
            tc.line(tc.cashId, 7000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.ledgerAccountId = tc.cashId
        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)
        XCTAssertEqual(vm.ledger?.rows.count, 2)

        vm.ledgerAccountId = tc.rentId
        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.rentId)
        XCTAssertEqual(vm.ledger?.rows.count, 1)
    }

    func testLedgerSelectionClearRemovesLoadedLedger() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.ledgerAccountId = tc.cashId
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)

        vm.ledgerAccountId = nil
        vm.reload()

        XCTAssertNil(vm.ledger)
        XCTAssertNil(vm.error)
    }

    func testReportDrillDownRoutesToEditVoucherSheet() {
        let router = AppRouter()
        let voucherId = UUID()

        ReportsNavigation.openVoucher(voucherId, router: router)

        guard case .editVoucher(let routedId) = router.presentedSheet else {
            return XCTFail("Expected edit voucher sheet to be presented")
        }
        XCTAssertEqual(routedId, voucherId)
    }
}
