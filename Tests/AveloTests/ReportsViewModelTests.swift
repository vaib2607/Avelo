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

    /// AVL-P1-036: `.priorMonth` must reconcile to a standalone run for the
    /// shifted month, and expose the matching column label — the same proof
    /// as prior-year, extended to a different configured mode.
    func testComparativePeriodPriorMonthReconcilesAndLabelsCorrectly() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-05-01", lines: [
            tc.line(tc.cashId, 15_000, .debit), tc.line(tc.salesId, 15_000, .credit)
        ]), in: tc.fy)
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: tc.fy)

        let asOf = DateFormatters.parseDate("2024-06-01")!
        let priorAsOf = ComparativePeriod.priorMonth.shift(asOf)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = asOf
        vm.comparativeEnabled = true
        vm.comparativePeriod = .priorMonth
        vm.reload()

        let standalone = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: priorAsOf, financialYearId: tc.fy.id).rows

        XCTAssertEqual(vm.comparativeTrialBalance, standalone)
        XCTAssertEqual(vm.comparativeColumnLabel, "Prior Month (₹)")
    }

    /// AVL-P1-036: `.priorQuarter` — same proof, different mode, confirming
    /// the DSL isn't special-cased to only work for month/year offsets.
    /// `ReportService.trialBalance` rejects an `asOfDate` before the target
    /// FY's start, so both dates (and their quarter-shifted comparative)
    /// stay inside `tc.fy`'s own range rather than needing a second FY.
    func testComparativePeriodPriorQuarterReconcilesAndLabelsCorrectly() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-04-15", lines: [
            tc.line(tc.cashId, 8_000, .debit), tc.line(tc.salesId, 8_000, .credit)
        ]), in: tc.fy)
        _ = try service.post(draft: tc.draft(on: "2024-07-15", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: tc.fy)

        let asOf = DateFormatters.parseDate("2024-07-15")!
        let priorAsOf = ComparativePeriod.priorQuarter.shift(asOf)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = asOf
        vm.comparativeEnabled = true
        vm.comparativePeriod = .priorQuarter
        vm.reload()

        let standalone = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: priorAsOf, financialYearId: tc.fy.id).rows

        XCTAssertEqual(vm.comparativeTrialBalance, standalone)
        XCTAssertEqual(vm.comparativeColumnLabel, "Prior Quarter (₹)")
    }

    /// AVL-P1-036 + H18-H19: atomic publish-on-failure must hold under a
    /// non-default configured mode too, not just the hardcoded prior-year
    /// path it was originally proven against. `.priorQuarter`'s 3-month
    /// offset gives enough room to reach outside `tc.fy`'s start (2024-04-01)
    /// without needing `asOf` itself to violate the FY-start validation.
    func testFailedComparativeRescopeLeavesSnapshotUnchangedUnderPriorQuarter() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2024-07-15", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.comparativeEnabled = true
        vm.comparativePeriod = .priorQuarter
        // asOf = 2024-07-15 -> priorQuarter = 2024-04-15, inside tc.fy itself: succeeds.
        vm.asOf = DateFormatters.parseDate("2024-07-15")!
        vm.reload()
        XCTAssertNil(vm.error)
        let snapshotPrimary = vm.trialBalance
        let snapshotComparative = vm.comparativeTrialBalance
        XCTAssertFalse(snapshotComparative.isEmpty)

        // asOf = 2024-04-15 (still >= tc.fy.startDate, so still a valid
        // primary request) -> priorQuarter = 2024-01-15, before tc.fy starts
        // and covered by no financial year at all: comparative fails.
        vm.asOf = DateFormatters.parseDate("2024-04-15")!
        vm.reload()

        XCTAssertNotNil(vm.error)
        XCTAssertEqual(vm.trialBalance, snapshotPrimary,
                        "Primary must not advance when its paired comparative fails, regardless of configured mode")
        XCTAssertEqual(vm.comparativeTrialBalance, snapshotComparative)
    }

    /// Phase 2.1/2.2 (H18-H19 atomic comparative): a scope change whose
    /// comparative fetch fails (e.g. the new prior-year window falls in a
    /// gap with no financial year) must not publish a fresh primary column
    /// next to a stale comparative one from the previous scope. Trial
    /// Balance/P&L previously assigned the primary column before attempting
    /// the comparative fetch — a comparative failure left `trialBalance`
    /// updated to the new scope while `comparativeTrialBalance` silently
    /// kept its old value. Balance Sheet already had this atomic-publish
    /// protection (#9b); this proves Trial Balance now has it too.
    func testFailedComparativeRescopeLeavesEntireTrialBalanceSnapshotUnchanged() throws {
        let tc = try TestCompany.make()
        // A short prior FY covering only part of the prior-year window,
        // leaving a real gap for a later rescope to fall into.
        let shortPriorFY = FinancialYear(
            companyId: tc.companyId, label: "2023 short",
            startDate: DateFormatters.parseDate("2023-04-01")!,
            endDate: DateFormatters.parseDate("2023-09-30")!,
            booksBeginDate: DateFormatters.parseDate("2023-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(shortPriorFY)
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try service.post(draft: tc.draft(on: "2023-04-15", lines: [
            tc.line(tc.cashId, 11_100, .debit), tc.line(tc.salesId, 11_100, .credit)
        ]), in: shortPriorFY)
        _ = try service.post(draft: tc.draft(on: "2024-04-15", lines: [
            tc.line(tc.cashId, 25_000, .debit), tc.line(tc.salesId, 25_000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = DateFormatters.parseDate("2024-04-15")!
        vm.comparativeEnabled = true
        vm.reload()
        XCTAssertNil(vm.error)
        let snapshotPrimary = vm.trialBalance
        let snapshotComparative = vm.comparativeTrialBalance
        XCTAssertFalse(snapshotComparative.isEmpty)

        // Prior-year date now lands in the gap after shortPriorFY ends.
        vm.asOf = DateFormatters.parseDate("2024-11-01")!
        vm.reload()

        XCTAssertNotNil(vm.error, "The failed comparative fetch must surface an error")
        XCTAssertEqual(vm.trialBalance, snapshotPrimary,
                        "Primary must not silently advance to the new scope when its paired comparative fails")
        XCTAssertEqual(vm.comparativeTrialBalance, snapshotComparative,
                        "Comparative must not remain a stale mismatch from a different scope than primary")
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

    /// H14-H17 (Day Book durable loop): a `dataRevision`-driven reload (fired
    /// after an Edit/Reverse dismiss) must reuse the existing `selectedDay`
    /// scope rather than resetting it, and must keep the row selection intact
    /// as long as the selected voucher still appears in the reloaded rows.
    func testDayBookReloadPreservesSelectedDayAndValidSelection() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(draft: tc.draft(on: "2024-06-05", lines: [
            tc.line(tc.cashId, 15000, .debit),
            tc.line(tc.salesId, 15000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .dayBook
        vm.selectedDay = DateFormatters.parseDate("2024-06-05")!
        vm.loadDayBook(day: vm.selectedDay)
        vm.selectedDayBookVoucherId = posted.voucher.id
        XCTAssertEqual(vm.dayBook.count, 1)

        // Simulate the ReportsView.onChange(of: env.dataRevision) reload path
        // that runs after a voucher edit/reverse dismisses back to Day Book.
        vm.reload()

        XCTAssertEqual(vm.selectedDay, DateFormatters.parseDate("2024-06-05")!,
                        "Reload triggered by a data-change notification must not reset the browsed day")
        XCTAssertEqual(vm.dayBook.count, 1)
        XCTAssertEqual(vm.selectedDayBookVoucherId, posted.voucher.id,
                        "A still-present row's selection must survive the reload")
    }

    /// H14-H17: once a selected Day Book row's voucher no longer appears for
    /// the browsed day (e.g. it was reversed and reversal moved/removed it),
    /// the stale selection must be cleared rather than silently pointing at a
    /// row that no longer exists in the refreshed table.
    func testDayBookReloadClearsSelectionWhenVoucherNoLongerPresentForDay() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(draft: tc.draft(on: "2024-06-05", lines: [
            tc.line(tc.cashId, 15000, .debit),
            tc.line(tc.salesId, 15000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .dayBook
        vm.selectedDay = DateFormatters.parseDate("2024-06-05")!
        vm.loadDayBook(day: vm.selectedDay)
        vm.selectedDayBookVoucherId = posted.voucher.id

        // Move the browsed day away from the voucher's date, matching what a
        // reload after cancel/reverse against a different day would see.
        vm.selectedDay = DateFormatters.parseDate("2024-06-06")!
        vm.loadDayBook(day: vm.selectedDay)

        XCTAssertTrue(vm.dayBook.isEmpty)
        XCTAssertNil(vm.selectedDayBookVoucherId,
                      "Selection must not silently reference a row absent from the current day's rows")
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

    // MARK: - H20-H21 zoom/restoration

    func testOpenLedgerPushesReturnContextAndRestoresPriorSelectionOnBack() throws {
        let tc = try TestCompany.make()
        let router = AppRouter()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .trialBalance
        vm.asOf = DateFormatters.parseDate("2024-06-01")!

        ReportsNavigation.openLedger(tc.cashId, vm: vm, router: router, dataRevision: 0)

        XCTAssertEqual(vm.selection, .ledger)
        XCTAssertEqual(vm.ledgerAccountId, tc.cashId)
        XCTAssertEqual(router.browseReturnStack.count, 1)

        ReportsNavigation.returnToPreviousReport(vm: vm, router: router)

        XCTAssertEqual(vm.selection, .trialBalance)
        XCTAssertTrue(router.browseReturnStack.isEmpty)
    }

    func testBackAffordanceAbsentWithEmptyReturnStack() {
        let router = AppRouter()
        XCTAssertTrue(router.browseReturnStack.isEmpty)
    }

    func testRepeatedDrillsProduceCorrectLIFOReturnOrder() throws {
        let tc = try TestCompany.make()
        let router = AppRouter()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .profitLoss

        ReportsNavigation.openLedger(tc.cashId, vm: vm, router: router, dataRevision: 0)
        XCTAssertEqual(vm.selection, .ledger)

        // Simulate a second drill from a different report onto the ledger,
        // without returning first — the stack must hold both.
        vm.selection = .outstanding
        ReportsNavigation.openLedger(tc.salesId, vm: vm, router: router, dataRevision: 0)
        XCTAssertEqual(router.browseReturnStack.count, 2)

        ReportsNavigation.returnToPreviousReport(vm: vm, router: router)
        XCTAssertEqual(vm.selection, .outstanding, "Most recently pushed context returns first")

        ReportsNavigation.returnToPreviousReport(vm: vm, router: router)
        XCTAssertEqual(vm.selection, .profitLoss, "Original context returns last")
        XCTAssertTrue(router.browseReturnStack.isEmpty)
    }

    func testReturnContextFromDifferentCompanyIsDiscardedNotApplied() throws {
        let tc = try TestCompany.make()
        let router = AppRouter()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger

        router.pushBrowseReturnContext(.init(
            companyId: UUID(), // a different company than vm.companyId
            financialYearId: tc.fy.id,
            surface: .report(.trialBalance),
            dataRevision: 0
        ))

        ReportsNavigation.returnToPreviousReport(vm: vm, router: router)

        XCTAssertEqual(vm.selection, .ledger, "A stale cross-company context must not be applied")
        XCTAssertTrue(router.browseReturnStack.isEmpty, "The stale context is still consumed, just not applied")
    }

    func testDrillEditVoucherReturnPreservesSelectionWithoutStackInvolvement() {
        let router = AppRouter()
        let voucherId = UUID()

        ReportsNavigation.openVoucher(voucherId, router: router)

        XCTAssertTrue(router.browseReturnStack.isEmpty,
                       "Voucher drill-in is a modal sheet over the unchanged report; it must not touch the return stack")
    }
}
