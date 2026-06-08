import XCTest
@testable import Mally

final class RCStressTests: XCTestCase {

    private func voucherDate(offsetDays: Int) -> String {
        let start = DateFormatters.parseDate("2024-04-01")!
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: start)!
        return DateFormatters.formatIsoDate(date)
    }

    func testVoucherVolumeStressKeepsBooksBalanced() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        for day in 0..<500 {
            let amount = Int64(1_000 + (day % 97) * 25)

            let lines: [VoucherDraft.Line]
            if day.isMultiple(of: 2) {
                lines = [
                    tc.line(tc.cashId, amount, .debit),
                    tc.line(tc.salesId, amount, .credit)
                ]
            } else {
                lines = [
                    tc.line(tc.rentId, amount, .debit),
                    tc.line(tc.cashId, amount, .credit)
                ]
            }

            _ = try service.post(
                draft: tc.draft(on: voucherDate(offsetDays: day % 365), narration: "Stress \(day)", lines: lines),
                in: tc.fy
            )
        }

        let totals = try tc.db.queryOne(
            """
            SELECT
              COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END), 0) AS dr,
              COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END), 0) AS cr,
              COUNT(DISTINCT voucher_id) AS voucher_count
            FROM mally_ledger_lines
            """
        ) { ($0.int("dr"), $0.int("cr"), $0.int("voucher_count")) }

        XCTAssertEqual(totals?.0, totals?.1)
        XCTAssertEqual(totals?.2, 500)
    }

    func testRepeatedReportGenerationStressRemainsStable() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let reports = ReportService(db: tc.db, companyId: tc.companyId)

        for day in 0..<120 {
            let amount = Int64(2_000 + day * 10)

            _ = try service.post(
                draft: tc.draft(
                    on: voucherDate(offsetDays: day),
                    narration: "Report stress \(day)",
                    lines: [
                        tc.line(tc.cashId, amount, .debit),
                        tc.line(tc.salesId, amount, .credit)
                    ]
                ),
                in: tc.fy
            )
        }

        for _ in 0..<100 {
            let trialBalance = try reports.trialBalance(
                asOfDate: DateFormatters.parseDate("2024-08-31")!,
                financialYearId: tc.fy.id
            )
            XCTAssertEqual(trialBalance.totalDebitPaise, trialBalance.totalCreditPaise)

            let dayBook = try reports.dayBook(
                fromDate: DateFormatters.parseDate("2024-04-01")!,
                toDate: DateFormatters.parseDate("2024-08-31")!
            )
            XCTAssertEqual(dayBook.count, 120)
        }
    }
}
