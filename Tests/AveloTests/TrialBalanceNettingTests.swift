import XCTest
@testable import Avelo

final class TrialBalanceNettingTests: XCTestCase {

    func testTrialBalanceNetsOpeningAndMovementToOneClosingSide() throws {
        let tc = try TestCompany.make()
        let vouchers = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try vouchers.post(
            draft: tc.draft(
                on: "2024-04-15",
                narration: "Rent paid from cash",
                lines: [
                    tc.line(tc.rentId, 4000, .debit),
                    tc.line(tc.cashId, 4000, .credit)
                ]
            ),
            in: tc.fy
        )

        let report = try ReportService(db: tc.db, companyId: tc.companyId).trialBalance(
            asOfDate: DateFormatters.parseDate("2024-04-30")!,
            financialYearId: tc.fy.id
        )

        let cash = try XCTUnwrap(report.rows.first(where: { $0.id == tc.cashId }))
        XCTAssertEqual(cash.debitPaise, 6000)
        XCTAssertEqual(cash.creditPaise, 0)
    }
}
