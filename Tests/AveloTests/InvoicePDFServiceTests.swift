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

    func testExportFailsClosedWhenVisibleInvoiceLinesOverflow() throws {
        let tc = try TestCompany.make()
        let voucherId = UUID()
        let timestamp = DateFormatters.formatIsoTimestamp(Date())
        try tc.db.execute(
            """
            INSERT INTO avelo_vouchers
            (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
             narration, is_reversal, reversal_of_id, is_posted, total_paise, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(voucherId.uuidString),
                .text(tc.companyId.uuidString),
                .text(tc.fy.id.uuidString),
                .text(VoucherType.Code.sales.rawValue),
                .text("SLS-OVERFLOW"),
                .date(DateFormatters.parseDate("2024-06-15")!),
                .null,
                .text("Overflow invoice"),
                .bool(false),
                .null,
                .bool(true),
                .integer(Int64.max),
                .text(timestamp),
                .text(timestamp)
            ]
        )

        for (lineOrder, line) in [
            LedgerLine(
                companyId: tc.companyId,
                voucherId: voucherId,
                accountId: tc.salesId,
                amountPaise: Int64.max,
                side: .credit,
                lineOrder: 0
            ),
            LedgerLine(
                companyId: tc.companyId,
                voucherId: voucherId,
                accountId: tc.rentId,
                amountPaise: 1,
                side: .credit,
                lineOrder: 1
            )
        ].enumerated() {
            try tc.db.execute(
                """
                INSERT INTO avelo_ledger_lines
                (id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(line.id.uuidString),
                    .text(line.companyId.uuidString),
                    .text(line.voucherId.uuidString),
                    .text(line.accountId.uuidString),
                    .integer(line.amountPaise),
                    .text(line.side.rawValue),
                    .null,
                    .null,
                    .integer(Int64(lineOrder))
                ]
            )
        }

        XCTAssertThrowsError(try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucherId)) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule overflow, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
        }
    }
}
