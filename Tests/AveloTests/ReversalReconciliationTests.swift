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
///
/// Broader fixtures beyond the original single 2-line, single-FY case:
/// multi-line (5 ledgers), cross-financial-year (original FY locked after
/// posting, reversal lands in the newly opened FY per
/// `VoucherService.reversalFinancialYear`), and partial item-invoice return
/// (residual = sold minus returned, not a full reversal). Invoice PDF export
/// parity (`InvoicePDFService`) is covered separately by
/// `InvoicePDFParityTests`.
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

    /// Broader fixture beyond the original 2-line case: five ledger lines
    /// (3 debit, 2 credit) must each independently net to zero — proves the
    /// reversal flips every line, not just the first pair.
    func testMultiLineVoucherReversalNetsAllLedgersToZero() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 20_000, .debit),
            tc.line(tc.customerId, 30_000, .debit),
            tc.line(tc.rentId, 5_000, .debit),
            tc.line(tc.salesId, 40_000, .credit),
            tc.line(tc.supplierId, 15_000, .credit)
        ]), in: tc.fy).voucher

        _ = try service.reverse(posted.id, reason: "multi-line reversal")

        let netRows: [(String, Int64)] = try tc.db.query(
            """
            SELECT ledger_id, SUM(CASE WHEN debit_or_credit = 'debit' THEN amount_paise ELSE -amount_paise END)
            FROM trn_accounting
            WHERE company_id = ? AND voucher_id IN (?, (SELECT id FROM avelo_vouchers WHERE reversal_of_id = ?))
            GROUP BY ledger_id
            """,
            bind: [.text(tc.companyId.uuidString), .text(posted.id.uuidString), .text(posted.id.uuidString)]
        ) { row in (try row.requiredText("ledger_id"), row.int(1)) }

        XCTAssertEqual(netRows.count, 5, "All five distinct ledgers must appear in the original+reversal pair")
        for (ledgerId, net) in netRows {
            XCTAssertEqual(net, 0, "Ledger \(ledgerId) must net to zero paise across the original and its reversal")
        }
    }

    /// Broader fixture: reversing a voucher whose financial year has since
    /// been locked must land the reversal in the current open FY
    /// (`VoucherService.reversalFinancialYear`), not silently fail or write
    /// into the locked year — and the two legs must still net to zero even
    /// though they now live in different financial years.
    func testCrossFinancialYearReversalNetsAccountingTrackToZero() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 12_000, .debit),
            tc.line(tc.salesId, 12_000, .credit)
        ]), in: tc.fy).voucher

        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        let nextFY = FinancialYear(
            id: UUID(), companyId: tc.companyId, label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(nextFY)

        let reversal = try service.reverse(posted.id, reason: "cross-FY reversal")

        XCTAssertEqual(reversal.financialYearId, nextFY.id, "Reversal of a locked-FY voucher must land in the current open financial year")
        XCTAssertNotEqual(reversal.financialYearId, posted.financialYearId)

        let netRows: [(String, Int64)] = try tc.db.query(
            """
            SELECT ledger_id, SUM(CASE WHEN debit_or_credit = 'debit' THEN amount_paise ELSE -amount_paise END)
            FROM trn_accounting
            WHERE company_id = ? AND voucher_id IN (?, ?)
            GROUP BY ledger_id
            """,
            bind: [.text(tc.companyId.uuidString), .text(posted.id.uuidString), .text(reversal.id.uuidString)]
        ) { row in (try row.requiredText("ledger_id"), row.int(1)) }

        XCTAssertEqual(netRows.count, 2)
        for (ledgerId, net) in netRows {
            XCTAssertEqual(net, 0, "Ledger \(ledgerId) must net to zero paise across FYs")
        }
    }

    /// Broader fixture: a partial item-invoice return (less than the full
    /// sold quantity) must leave the canonical accounting/inventory tracks
    /// showing exactly the residual — sold minus returned — not zero and
    /// not the full original. Complements the existing full-reversal-nets-
    /// to-zero proofs with the partial case named in Rev3 §4.6.
    func testPartialItemInvoiceReturnLeavesCorrectResidualAcrossCanonicalTracks() throws {
        let tc = try TestCompany.make()
        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV"
        try CompanyRepository(db: tc.db).update(company)
        var customer = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId))
        customer.gstin = "29AAGCB7383J1Z4"
        try AccountRepository(db: tc.db).update(customer)

        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "PARTIAL-RET", name: "Partial Return Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 10, ratePaise: 100)

        let sale = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).post(
            voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.customerId, salesOrPurchaseLedgerId: tc.salesId,
            items: [.init(itemId: item.id, quantity: 6, ratePaise: 100)], narration: "sale", in: tc.fy
        )
        let source = try XCTUnwrap(InventoryRepository(db: tc.db).listMovements(forVoucher: sale.voucher.id).first)

        let returnDraft = VoucherDraft(
            mode: .create, entryMode: .itemInvoice, voucherTypeCode: .creditNote,
            date: DateFormatters.parseDate("2024-06-05")!, partyAccountId: tc.customerId, narration: "partial return",
            lines: [
                .init(accountId: tc.customerId, amountPaise: 200, side: .credit, lineOrder: 0),
                .init(accountId: tc.salesId, amountPaise: 200, side: .debit, lineOrder: 1)
            ]
        )
        _ = try ItemInvoiceReturnService(db: tc.db, companyId: tc.companyId).post(.init(
            draft: returnDraft, financialYear: tc.fy,
            lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(2))],
            reason: "customer partial return"
        ))

        // Residual = 6 sold - 2 returned = 4 units. Scoped to movements on/
        // after the sale date so the fixture's own May opening stock-in
        // (10 units, unrelated to this sale/return pair) isn't counted.
        let rawResidualQty = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity_numerator ELSE -quantity_numerator END), 0)
            FROM trn_inventory WHERE company_id = ? AND stock_item_id = ? AND date >= ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(item.id.uuidString), .date(DateFormatters.parseDate("2024-06-01")!)]
        ) { $0.int(0) })

        XCTAssertEqual(rawResidualQty, 4, "Net outgoing quantity must equal sold minus returned, not zero and not the full sale")
    }
}
