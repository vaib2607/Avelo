import XCTest
@testable import Avelo

final class FinancialYearCloseCarryForwardTests: XCTestCase {

    func testCloseCarriesBalancesIntoNextFinancialYearExactlyOnce() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)
        let repo = FinancialYearRepository(db: tc.db)

        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try repo.insert(nextFY)

        let voucherService = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try voucherService.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50_000, .debit),
            tc.line(tc.salesId, 50_000, .credit)
        ]), in: tc.fy)

        try service.close(tc.fy.id)

        let carried = try FinancialYearOpeningBalanceRepository(db: tc.db).listForFinancialYear(nextFY.id)
        XCTAssertFalse(carried.isEmpty)

        let byAccount = Dictionary(uniqueKeysWithValues: carried.map { ($0.accountId, $0) })
        XCTAssertEqual(byAccount[tc.cashId]?.openingBalancePaise, 60_000)
        XCTAssertEqual(byAccount[tc.cashId]?.openingBalanceSide, .debit)
        XCTAssertEqual(byAccount[tc.salesId]?.openingBalancePaise, 50_000)
        XCTAssertEqual(byAccount[tc.salesId]?.openingBalanceSide, .credit)

        try service.close(tc.fy.id)
        let carriedAgain = try FinancialYearOpeningBalanceRepository(db: tc.db).listForFinancialYear(nextFY.id)
        XCTAssertEqual(carriedAgain.count, carried.count)
    }

    func testLaterFinancialYearReportsUseCarriedOpeningBalances() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)
        let repo = FinancialYearRepository(db: tc.db)

        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try repo.insert(nextFY)

        let voucherService = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try voucherService.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50_000, .debit),
            tc.line(tc.salesId, 50_000, .credit)
        ]), in: tc.fy)
        try service.close(tc.fy.id)

        let report = ReportService(db: tc.db, companyId: tc.companyId)
        let ledger = try report.ledger(
            accountId: tc.cashId,
            financialYearId: nextFY.id,
            fromDate: nextFY.startDate,
            toDate: nextFY.endDate
        )
        XCTAssertEqual(ledger.openingBalancePaise, 60_000)
        XCTAssertEqual(ledger.closingBalancePaise, 60_000)

        let trialBalance = try report.trialBalance(asOfDate: nextFY.endDate, financialYearId: nextFY.id)
        let cash = try XCTUnwrap(trialBalance.rows.first(where: { $0.id == tc.cashId }))
        XCTAssertEqual(cash.debitPaise, 60_000)
        XCTAssertEqual(cash.creditPaise, 0)
    }

    func testReopenRemovesCarriedOpeningBalancesAndRestoresOpenState() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)
        let repo = FinancialYearRepository(db: tc.db)

        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try repo.insert(nextFY)
        try service.close(tc.fy.id)

        XCTAssertFalse(try FinancialYearOpeningBalanceRepository(db: tc.db).listForFinancialYear(nextFY.id).isEmpty)

        try service.reopen(tc.fy.id, reason: "test")

        XCTAssertTrue(try FinancialYearOpeningBalanceRepository(db: tc.db).listForFinancialYear(nextFY.id).isEmpty)
        let reopened = try XCTUnwrap(repo.findById(tc.fy.id))
        XCTAssertFalse(reopened.isClosed)
        XCTAssertFalse(reopened.isLocked)
    }

    func testCloseRequiresNextFinancialYear() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try service.close(tc.fy.id)) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("next financial year"))
        }
    }
}
