import XCTest
@testable import Avelo

@MainActor
final class ReportsViewModelTests: XCTestCase {

    private func priorFinancialYear(for tc: TestCompany) throws -> FinancialYear {
        let start = DateFormatters.parseDate("2023-04-01")!
        let financialYear = FinancialYear(
            companyId: tc.companyId,
            label: "2023-24",
            startDate: start,
            endDate: DateFormatters.parseDate("2024-03-31")!,
            booksBeginDate: start
        )
        try FinancialYearRepository(db: tc.db).insert(financialYear)
        return financialYear
    }

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

    func testBalanceSheetSelectionLoadsReportAndClearsPriorError() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25_000, .debit),
            tc.line(tc.salesId, 25_000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.error = .notFound("Previous report failure")

        vm.selection = .balanceSheet
        vm.asOf = tc.fy.endDate
        vm.reload()

        XCTAssertNotNil(vm.balanceSheet)
        XCTAssertNil(vm.error)
    }

    // AVL-P1-036 (Alt+N comparative columns): the comparative column must
    // reconcile exactly to what the same report returns standalone for that
    // prior period — no separate math, no drift.

    func testComparativeTrialBalanceReconcilesToStandaloneRunForPriorYear() throws {
        let tc = try TestCompany.make()
        let priorFY = try priorFinancialYear(for: tc)
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2023-06-01", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: priorFY)
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
            .trialBalance(asOfDate: priorAsOf, financialYearId: priorFY.id).rows

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
        let priorFY = try priorFinancialYear(for: tc)
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2023-06-01", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: priorFY)
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
            .profitAndLoss(fromDate: priorFrom, toDate: priorTo, financialYearId: priorFY.id)

        XCTAssertEqual(vm.comparativeProfitLoss, standalone)
    }

    func testComparativeBalanceSheetReconcilesToStandaloneRunForPriorYear() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let priorFY = FinancialYear(
            companyId: tc.companyId,
            label: "2023-24",
            startDate: DateFormatters.parseDate("2023-04-01")!,
            endDate: DateFormatters.parseDate("2024-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2023-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(priorFY)
        _ = try service.post(draft: tc.draft(on: "2023-06-01", lines: [
            tc.line(tc.cashId, 12_000, .debit),
            tc.line(tc.salesId, 12_000, .credit)
        ]), in: priorFY)
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
            .balanceSheet(asOfDate: priorAsOf, financialYearId: priorFY.id)

        XCTAssertEqual(vm.comparativeBalanceSheet, standalone)
    }

    func testBalanceSheetScopeFailureClearsResultAndSurfacesLocalError() throws {
        let tc = try TestCompany.make()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .balanceSheet
        vm.asOf = DateFormatters.parseDate("2024-03-31")!

        vm.reload()

        XCTAssertNil(vm.balanceSheet)
        XCTAssertFalse(vm.isLoading)
        guard case .validation(let error) = vm.error else {
            return XCTFail("Expected typed Balance Sheet scope error")
        }
        XCTAssertEqual(error.code, .reportAsOfBeforeFinancialYear)
        guard case .primary(.validation(let requestValidation)) = vm.balanceSheetRequestError else {
            return XCTFail("Expected primary scoped request error preserving AppError")
        }
        XCTAssertEqual(requestValidation.code, .reportAsOfBeforeFinancialYear)
    }

    func testSameCompanyFinancialYearResetClearsOldBalanceSheetAndUsesNewScope() throws {
        let tc = try TestCompany.make()
        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(nextFY)
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .balanceSheet
        vm.asOf = tc.fy.endDate
        vm.reload()
        XCTAssertNotNil(vm.balanceSheet)

        vm.resetFinancialYear(nextFY)

        XCTAssertEqual(vm.fyId, nextFY.id)
        XCTAssertEqual(vm.asOf, nextFY.endDate)
        XCTAssertNil(vm.error)
        XCTAssertNil(vm.balanceSheetRequestError)
        XCTAssertNotNil(vm.balanceSheet)
    }

    func testComparativeBalanceSheetFailurePublishesNeitherPeriodAndKeepsComparativeIdentity() throws {
        let tc = try TestCompany.make()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .balanceSheet
        vm.asOf = DateFormatters.parseDate("2024-06-01")!
        vm.comparativeEnabled = true // There is deliberately no FY for 2023-06-01.

        vm.reload()

        XCTAssertNil(vm.balanceSheet)
        XCTAssertNil(vm.comparativeBalanceSheet)
        XCTAssertFalse(vm.isLoading)
        guard case .comparative = vm.balanceSheetRequestError else {
            return XCTFail("Expected the comparative scope to retain its error identity")
        }
        XCTAssertEqual(vm.balanceSheetErrorAsOf, DateFormatters.parseDate("2023-06-01")!)
    }

    func testFinancialYearResetOutsideBalanceSheetDoesNotRunHiddenBalanceSheetLoad() throws {
        let tc = try TestCompany.make()
        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(nextFY)
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance

        vm.resetFinancialYear(nextFY)

        XCTAssertEqual(vm.fyId, nextFY.id)
        XCTAssertNil(vm.balanceSheet)
        XCTAssertNil(vm.balanceSheetRequestError)
        XCTAssertFalse(vm.isLoading)
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
