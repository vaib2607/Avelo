import XCTest
import PDFKit
@testable import Avelo

/// Rev3 §4.6 report/export parity: proves `InvoicePDFService`'s rendered
/// grand total is the same number as an independent raw SQL sum over
/// `trn_accounting` for the invoice's party account — the same
/// authoritative-SQL-vs-live pattern already used for trial balance/P&L/
/// stock valuation/GST summary, extended to the PDF export path.
/// `InvoicePDFServiceTests` already proves individual line items and tax
/// breakdowns render correctly; this proves the rendered total specifically
/// cannot drift from the underlying posted ledger data.
final class InvoicePDFParityTests: XCTestCase {

    func testRenderedGrandTotalReconcilesToRawPartyLedgerSum() throws {
        let tc = try TestCompany.make()
        let companyRepo = CompanyRepository(db: tc.db)
        var company = try XCTUnwrap(companyRepo.findById(tc.companyId))
        company.gstin = "27ABCDE1234F1Z5"
        try companyRepo.update(company)

        let accounts = AccountRepository(db: tc.db)
        let customerId = UUID()
        let debtorGroupId = try XCTUnwrap(accounts.findById(tc.customerId)).groupId
        try tc.db.execute(
            """
            INSERT INTO avelo_accounts
            (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
             is_active, is_bank_account, gstin, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(customerId.uuidString), .text(tc.companyId.uuidString), .text(debtorGroupId.uuidString),
                .text("CUST-PARITY"), .text("Parity Traders"), .integer(0), .text("debit"),
                .bool(true), .bool(false), .text("27ABCDE1234F1Z5"),
                .text(DateFormatters.formatIsoTimestamp(Date())), .text(DateFormatters.formatIsoTimestamp(Date()))
            ]
        )
        let customer = try XCTUnwrap(accounts.findById(customerId))

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer.id, narration: "Parity invoice",
            lines: [
                .init(accountId: customer.id, amountPaise: 129_800, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 110_000, side: .credit),
                .init(accountId: tc.cgstOutputId, amountPaise: 9_900, side: .credit),
                .init(accountId: tc.sgstOutputId, amountPaise: 9_900, side: .credit)
            ]
        ), in: tc.fy).voucher

        let rawTotal = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(amount_paise), 0)
            FROM trn_accounting
            WHERE company_id = ? AND voucher_id = ? AND ledger_id = ? AND debit_or_credit = 'debit'
            """,
            bind: [.text(tc.companyId.uuidString), .text(voucher.id.uuidString), .text(customer.id.uuidString)]
        ) { $0.int(0) })

        XCTAssertEqual(rawTotal, 129_800)

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let document = PDFDocument(data: pdfData)
        let text = (document?.string ?? "") + "\n" + ((document?.page(at: 0)?.string) ?? "")

        XCTAssertTrue(text.contains(Currency.formatPaise(rawTotal)),
                      "PDF-rendered grand total must reconcile to the raw party-ledger debit sum, not a value recomputed by the PDF layer")
    }
}
