import XCTest
import PDFKit
@testable import Avelo

final class InvoicePDFServiceTests: XCTestCase {

    func testExportsTaxInvoicePdfForSalesVoucher() throws {
        let tc = try TestCompany.make()
        let companyRepo = CompanyRepository(db: tc.db)
        var company = try XCTUnwrap(companyRepo.findById(tc.companyId))
        company.name = "Avelo Steel Pvt Ltd"
        company.addressLine1 = "Plot 42, Industrial Estate"
        company.addressLine2 = "Sector 8"
        company.city = "Nagpur"
        company.state = "Maharashtra"
        company.pincode = "440001"
        company.gstin = "27ABCDE1234F1Z5"
        try companyRepo.update(company)

        let accounts = AccountRepository(db: tc.db)
        let customerId = UUID()
        try tc.db.execute(
            """
            INSERT INTO avelo_accounts
            (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
             is_active, is_bank_account, gstin, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(customerId.uuidString),
                .text(tc.companyId.uuidString),
                .text(tc.assetsGroupId.uuidString),
                .text("CUST-001"),
                .text("Acme Traders"),
                .integer(0),
                .text("debit"),
                .bool(true),
                .bool(false),
                .text("27ABCDE1234F1Z5"),
                .text(DateFormatters.formatIsoTimestamp(Date())),
                .text(DateFormatters.formatIsoTimestamp(Date()))
            ]
        )
        let customer = try XCTUnwrap(accounts.findById(customerId))

        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let voucher = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer.id,
            narration: "Test tax invoice",
            lines: [
                .init(accountId: customer.id, amountPaise: 118000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit, taxCode: "7208"),
                .init(accountId: tc.rentId, amountPaise: 18000, side: .credit, taxCode: "GST18")
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        XCTAssertTrue(pdfData.starts(with: Data("%PDF".utf8)))

        let document = PDFDocument(data: pdfData)
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.pageCount, 1)

        let fullText = (document?.string ?? "") + "\n" + ((document?.page(at: 0)?.string) ?? "")
        XCTAssertTrue(fullText.contains("TAX INVOICE"))
        XCTAssertTrue(fullText.contains("Avelo Steel Pvt Ltd"))
        XCTAssertTrue(fullText.contains("27ABCDE1234F1Z5"))
        XCTAssertTrue(fullText.contains("Acme Traders"))
        XCTAssertTrue(fullText.contains("Test tax invoice"))
        XCTAssertTrue(fullText.contains("7208"))
        XCTAssertTrue(fullText.contains(Currency.formatPaise(118000)))
        XCTAssertTrue(fullText.contains(voucher.number))
    }
}
