import XCTest
@testable import Avelo

/// Rev3 §4.6 report/export parity: proves `ReportService.outstanding`'s
/// reported total reconciles against an independent raw SQL sum over
/// `avelo_bill_allocations` signed by the party's ledger side — the same
/// authoritative-SQL-vs-live pattern as trial balance/P&L/stock valuation.
/// This does not re-derive `BillAllocationEngine`'s FIFO bill-matching order
/// (that's a display concern for which bill a receipt settles first); the
/// accounting identity under test — total outstanding equals total billed
/// minus total settled, regardless of match order — holds independent of
/// FIFO layering, so a plain signed sum is a valid authoritative source.
final class OutstandingReconciliationTests: XCTestCase {

    func testReceivableTotalReconcilesToRawBillAllocationSum() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.customerId,
            billReferenceType: .newRef, billReferenceNumber: "INV-1",
            narration: "Sale 1",
            lines: [
                tc.line(tc.customerId, 40_000, .debit),
                tc.line(tc.salesId, 40_000, .credit)
            ]
        ), in: tc.fy, workflow: .init(billAllocationKind: .newRef, billAllocationNumber: "INV-1"))

        _ = try service.post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-05")!,
            partyAccountId: tc.customerId,
            billReferenceType: .newRef, billReferenceNumber: "INV-2",
            narration: "Sale 2",
            lines: [
                tc.line(tc.customerId, 25_000, .debit),
                tc.line(tc.salesId, 25_000, .credit)
            ]
        ), in: tc.fy, workflow: .init(billAllocationKind: .newRef, billAllocationNumber: "INV-2"))

        _ = try service.post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .receipt,
            date: DateFormatters.parseDate("2024-06-10")!,
            partyAccountId: tc.customerId,
            billReferenceType: .agstRef, billReferenceNumber: "INV-1",
            narration: "Partial receipt",
            lines: [
                tc.line(tc.cashId, 15_000, .debit),
                tc.line(tc.customerId, 15_000, .credit)
            ]
        ), in: tc.fy, workflow: .init(billAllocationKind: .agstRef, billAllocationNumber: "INV-1"))

        let report = try ReportService(db: tc.db, companyId: tc.companyId).outstanding(
            asOfDate: DateFormatters.parseDate("2024-06-30")!,
            direction: .receivable
        )

        let rawTotal = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN l.side = 'debit' THEN ba.allocated_paise ELSE -ba.allocated_paise END), 0)
            FROM avelo_bill_allocations ba
            JOIN trn_accounting_compat l ON l.voucher_id = ba.voucher_id
                AND l.company_id = ba.company_id AND l.account_id = ba.party_account_id
            WHERE ba.company_id = ? AND ba.party_account_id = ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(tc.customerId.uuidString)]
        ) { $0.int(0) })

        XCTAssertEqual(report.totalPaise, rawTotal, "Reported receivable total must reconcile to the raw bill-allocation ledger sum")
        XCTAssertEqual(report.totalPaise, 50_000, "40,000 + 25,000 billed minus 15,000 settled")
    }
}
