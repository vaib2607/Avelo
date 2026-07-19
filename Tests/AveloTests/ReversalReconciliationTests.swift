import XCTest
@testable import Avelo

/// Rev3 §4.6/§4.7 reversal parity: `VoucherService.reverse` creates flipped
/// ledger lines for a plain (non-item-invoice) voucher. This proves raw SQL
/// over the canonical `trn_accounting` track agrees the original plus its
/// reversal nets to zero per ledger account — the same authoritative-SQL-vs-
/// live pattern used for trial balance/P&L/stock valuation, applied to the
/// reversal path specifically. Item-invoice reversal parity is covered
/// separately by `ItemInvoiceServiceTests
/// .testItemInvoiceReversalNetsCanonicalTracksToZero` since it exercises a
/// different code path (both accounting and inventory tracks).
final class ReversalReconciliationTests: XCTestCase {

    func testPlainVoucherReversalNetsAccountingTrackToZero() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 75_000, .debit),
            tc.line(tc.salesId, 75_000, .credit)
        ]), in: tc.fy).voucher

        _ = try service.reverse(posted.id, reason: "test reversal")

        let netRows: [(String, Int64)] = try tc.db.query(
            """
            SELECT ledger_id, SUM(CASE WHEN debit_or_credit = 'debit' THEN amount_paise ELSE -amount_paise END)
            FROM trn_accounting
            WHERE company_id = ? AND voucher_id IN (?, (SELECT id FROM avelo_vouchers WHERE reversal_of_id = ?))
            GROUP BY ledger_id
            """,
            bind: [.text(tc.companyId.uuidString), .text(posted.id.uuidString), .text(posted.id.uuidString)]
        ) { row in (try row.requiredText("ledger_id"), row.int(1)) }

        XCTAssertEqual(netRows.count, 2, "Both cash and sales ledgers must appear in the original+reversal pair")
        for (ledgerId, net) in netRows {
            XCTAssertEqual(net, 0, "Ledger \(ledgerId) must net to zero paise across the original and its reversal")
        }
    }
}
