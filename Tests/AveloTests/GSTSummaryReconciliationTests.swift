import XCTest
@testable import Avelo

/// Rev3 §4.6 report/export parity: proves `ReportService.gstSummary`'s
/// output/input tax totals reconcile against an independent raw SQL sum
/// over `trn_accounting` for the GST ledger accounts — the same
/// authoritative-SQL-vs-live pattern as trial balance/P&L/stock valuation,
/// extended to the GST compliance report. Uses direct journal postings to
/// the GST accounts (not `ItemInvoiceService`) so this isolates
/// `ReportService.gstSummary`'s own aggregation from item-invoice GST
/// computation, which is already covered separately by
/// `ItemInvoiceServiceTests` (e.g. `testSalesItemInvoicePostsIGSTForInterState`).
///
/// Outstanding, Cash Flow, and Stock Ageing parity are covered separately by
/// `OutstandingReconciliationTests`, `CashFlowReconciliationTests`, and
/// `StockAgeingReconciliationTests`. Invoice PDF export has no reconciliation
/// harness — the feature does not exist in this codebase (Rev3 §4.6).
final class GSTSummaryReconciliationTests: XCTestCase {

    func testGstSummaryOutputAndInputTaxReconcileToRawLedgerSums() throws {
        let tc = try TestCompany.make()
        let accountRepo = AccountRepository(db: tc.db)
        let cgstInput = Account(companyId: tc.companyId, groupId: tc.liabilityGroupId, code: "CGST_INPUT", name: "CGST Input",
                                 openingBalancePaise: 0, openingBalanceSide: .debit)
        try accountRepo.insert(cgstInput)

        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        // Sale with output GST collected.
        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 11_800, .debit),
            tc.line(tc.salesId, 10_000, .credit),
            tc.line(tc.cgstOutputId, 900, .credit),
            tc.line(tc.sgstOutputId, 900, .credit)
        ]), in: tc.fy)
        // Purchase with input GST paid.
        _ = try service.post(draft: tc.draft(on: "2024-06-05", lines: [
            tc.line(tc.rentId, 5_000, .debit),
            tc.line(cgstInput.id, 250, .debit),
            tc.line(tc.cashId, 5_250, .credit)
        ]), in: tc.fy)

        let summary = try ReportService(db: tc.db, companyId: tc.companyId).gstSummary(
            fromDate: DateFormatters.parseDate("2024-06-01")!,
            toDate: DateFormatters.parseDate("2024-06-30")!
        )

        func rawNet(_ accountId: Account.ID, side: String) throws -> Int64 {
            try XCTUnwrap(tc.db.queryOne(
                """
                SELECT COALESCE(SUM(CASE WHEN debit_or_credit = ? THEN amount_paise ELSE -amount_paise END), 0)
                FROM trn_accounting WHERE company_id = ? AND ledger_id = ?
                """,
                bind: [.text(side), .text(tc.companyId.uuidString), .text(accountId.uuidString)]
            ) { $0.int(0) })
        }

        let rawOutputTax = try rawNet(tc.cgstOutputId, side: "credit") + rawNet(tc.sgstOutputId, side: "credit")
        let rawInputTax = try rawNet(cgstInput.id, side: "debit")

        XCTAssertEqual(summary.outputTaxPaise, rawOutputTax, "Reported output tax must reconcile to the raw canonical ledger sum")
        XCTAssertEqual(summary.inputTaxPaise, rawInputTax, "Reported input tax must reconcile to the raw canonical ledger sum")
        XCTAssertEqual(summary.netPayablePaise, rawOutputTax - rawInputTax)
    }
}
