import XCTest
@testable import Avelo

/// Rev3 §4.6 report/export parity: proves `ReportService.cashFlow`'s
/// reported net cash movement reconciles against an independent raw SQL net
/// over `trn_accounting` for the cash/bank ledgers themselves — the same
/// authoritative-SQL-vs-live pattern as trial balance/P&L/stock valuation.
/// This is a real accounting identity (net cash flow == change in cash/bank
/// balance over the period) independent of the operating/investing/
/// financing section classification, so it catches a join/filter bug in the
/// report's own aggregation without re-deriving that classification logic.
final class CashFlowReconciliationTests: XCTestCase {

    func testNetCashFlowReconcilesToRawCashLedgerMovement() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", narration: "Cash sale", lines: [
            tc.line(tc.cashId, 30_000, .debit),
            tc.line(tc.salesId, 30_000, .credit)
        ]), in: tc.fy)

        _ = try service.post(draft: tc.draft(on: "2024-06-10", narration: "Rent paid", lines: [
            tc.line(tc.rentId, 8_000, .debit),
            tc.line(tc.cashId, 8_000, .credit)
        ]), in: tc.fy)

        _ = try service.post(draft: tc.draft(on: "2024-06-15", narration: "Capital infusion", lines: [
            tc.line(tc.cashId, 5_000, .debit),
            tc.line(tc.capitalId, 5_000, .credit)
        ]), in: tc.fy)

        let fromDate = DateFormatters.parseDate("2024-06-01")!
        let toDate = DateFormatters.parseDate("2024-06-30")!
        let cashFlow = try ReportService(db: tc.db, companyId: tc.companyId).cashFlow(fromDate: fromDate, toDate: toDate)

        let rawNet = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN l.debit_or_credit = 'debit' THEN l.amount_paise ELSE -l.amount_paise END), 0)
            FROM trn_accounting l
            JOIN avelo_vouchers v ON v.id = l.voucher_id AND v.company_id = l.company_id
            WHERE l.company_id = ? AND l.ledger_id = ? AND v.is_posted = 1 AND v.date BETWEEN ? AND ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(tc.cashId.uuidString), .date(fromDate), .date(toDate)]
        ) { $0.int(0) })

        XCTAssertEqual(cashFlow.netCashFlowPaise, rawNet, "Reported net cash flow must reconcile to the raw cash-ledger movement")
        XCTAssertEqual(cashFlow.operatingNetPaise + cashFlow.investingNetPaise + cashFlow.financingNetPaise, cashFlow.netCashFlowPaise)
        XCTAssertEqual(cashFlow.netCashFlowPaise, 27_000, "30,000 - 8,000 + 5,000")
    }
}
