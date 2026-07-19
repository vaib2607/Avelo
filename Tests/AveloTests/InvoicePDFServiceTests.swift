import XCTest
import PDFKit
@testable import Avelo

final class InvoicePDFServiceTests: XCTestCase {

    /// Inserts a party (customer/vendor) account with the given GSTIN
    /// (or none), matching the raw-SQL fixture pattern the existing sales
    /// voucher test already uses (AccountService.createAccount doesn't
    /// expose company-level GSTIN input directly in test-friendly form).
    @discardableResult
    private func insertParty(_ tc: TestCompany, code: String, name: String, gstin: String?) throws -> Account.ID {
        let id = UUID()
        let debtorGroupId = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId)).groupId
        try tc.db.execute(
            """
            INSERT INTO avelo_accounts
            (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
             is_active, is_bank_account, gstin, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(id.uuidString),
                .text(tc.companyId.uuidString),
                .text(debtorGroupId.uuidString),
                .text(code),
                .text(name),
                .integer(0),
                .text("debit"),
                .bool(true),
                .bool(false),
                .optionalText(gstin),
                .text(DateFormatters.formatIsoTimestamp(Date())),
                .text(DateFormatters.formatIsoTimestamp(Date()))
            ]
        )
        return id
    }

    private func setCompanyGSTIN(_ tc: TestCompany, gstin: String) throws {
        let repo = CompanyRepository(db: tc.db)
        var company = try XCTUnwrap(repo.findById(tc.companyId))
        company.gstin = gstin
        try repo.update(company)
    }

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
        let debtorGroupId = try XCTUnwrap(accounts.findById(tc.customerId)).groupId
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
                .text(debtorGroupId.uuidString),
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
        XCTAssertEqual(try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .invoicePDFExported)).count, 0)

        let savedURL = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: savedURL) }
        try pdfData.write(to: savedURL, options: .atomic)
        try InvoicePDFService(db: tc.db).recordExportSaved(voucherId: voucher.id, url: savedURL)
        XCTAssertEqual(try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .invoicePDFExported)).count, 1)

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
                INSERT INTO trn_accounting
                (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, tax_code, cost_center, line_order, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    .integer(Int64(lineOrder)),
                    .text(timestamp)
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

    // AVL-P0-022: Core B2B tax invoice slice -- CGST/SGST/IGST breakdown,
    // place of supply, unregistered-party fallback, and inventory-linked
    // stock detail. Signed QR / e-invoice IRN is intentionally out of scope
    // (blocked by R-1, the offline-only rule).

    func testRendersCgstSgstBreakdownAndIntraStatePlaceOfSupplyForSameStateParty() throws {
        let tc = try TestCompany.make()
        try setCompanyGSTIN(tc, gstin: "27ABCDE1234F1Z5") // Maharashtra
        let customer = try insertParty(tc, code: "CUST-MH", name: "Pune Traders", gstin: "27PQRSX5678L1Z9") // also Maharashtra

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 118000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit),
                .init(accountId: tc.cgstOutputId, amountPaise: 9000, side: .credit),
                .init(accountId: tc.sgstOutputId, amountPaise: 9000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertTrue(text.contains("CGST"))
        XCTAssertTrue(text.contains("SGST"))
        XCTAssertFalse(text.contains("IGST"))
        XCTAssertTrue(text.contains(Currency.formatPaise(9000)))
        XCTAssertTrue(text.contains("Maharashtra"))
        XCTAssertTrue(text.contains("Intra-State"))
    }

    func testRendersIgstBreakdownAndInterStatePlaceOfSupplyForDifferentStateParty() throws {
        let tc = try TestCompany.make()
        try setCompanyGSTIN(tc, gstin: "27ABCDE1234F1Z5") // Maharashtra
        let customer = try insertParty(tc, code: "CUST-KA", name: "Bengaluru Traders", gstin: "29PQRSX5678L1Z9") // Karnataka

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 118000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit),
                .init(accountId: tc.igstOutputId, amountPaise: 18000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertTrue(text.contains("IGST"))
        XCTAssertFalse(text.contains("CGST"))
        XCTAssertFalse(text.contains("SGST"))
        XCTAssertTrue(text.contains(Currency.formatPaise(18000)))
        XCTAssertTrue(text.contains("Karnataka"))
        XCTAssertTrue(text.contains("Inter-State"))
    }

    func testRendersCessWhenPresent() throws {
        let tc = try TestCompany.make()
        let cessId = UUID()
        try tc.db.execute(
            "INSERT INTO avelo_account_groups (id, company_id, code, name, nature, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text("3600"), .text("Cess Group"), .text("liabilities"), .integer(5), .text(DateFormatters.formatIsoTimestamp(Date()))]
        )
        let cessGroup: Account.ID = try XCTUnwrap(tc.db.queryOne(
            "SELECT id FROM avelo_account_groups WHERE code = ? AND company_id = ?",
            bind: [.text("3600"), .text(tc.companyId.uuidString)]
        ) { row in try UUIDParsing.required(row.text("id"), field: "test.group.id") })
        try tc.db.execute(
            "INSERT INTO avelo_accounts (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [.text(cessId.uuidString), .text(tc.companyId.uuidString), .text(cessGroup.uuidString), .text("CESS"), .text("CESS"), .integer(0), .text("credit"), .text(DateFormatters.formatIsoTimestamp(Date())), .text(DateFormatters.formatIsoTimestamp(Date()))]
        )
        let customer = try insertParty(tc, code: "CUST-CESS", name: "Cess Customer", gstin: nil)

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 105000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit),
                .init(accountId: cessId, amountPaise: 5000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertTrue(text.contains("CESS"))
        XCTAssertTrue(text.contains(Currency.formatPaise(5000)))
    }

    func testUnregisteredPartyRendersFallbackWithoutPlaceOfSupplyAndDoesNotThrow() throws {
        let tc = try TestCompany.make()
        try setCompanyGSTIN(tc, gstin: "27ABCDE1234F1Z5")
        let customer = try insertParty(tc, code: "CUST-UNREG", name: "Retail Customer", gstin: nil)

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 100000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertTrue(text.contains("Unregistered"))
        XCTAssertFalse(text.contains("Place of Supply"))
    }

    func testInventoryLinkedVoucherRendersStockDetailSection() throws {
        let tc = try TestCompany.make()
        let customer = try insertParty(tc, code: "CUST-INV", name: "Inventory Customer", gstin: nil)
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "SKU-1", name: "Steel Rod", unit: "NOS")

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 120000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 120000, side: .credit)
            ]
        ), in: tc.fy).voucher

        _ = try InventoryService(db: tc.db, companyId: tc.companyId).recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-15")!,
            type: .stockIn,
            quantity: 10,
            ratePaise: 12000,
            voucherId: voucher.id
        )

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertTrue(text.contains("Stock Detail"))
        XCTAssertTrue(text.contains("Steel Rod"))
    }

    func testNonInventoryLinkedVoucherOmitsStockDetailSection() throws {
        let tc = try TestCompany.make()
        let customer = try insertParty(tc, code: "CUST-NOINV", name: "Service Customer", gstin: nil)

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: customer,
            lines: [
                .init(accountId: customer, amountPaise: 100000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let pdfData = try InvoicePDFService(db: tc.db).exportTaxInvoicePDF(voucherId: voucher.id)
        let text = pdfText(pdfData)

        XCTAssertFalse(text.contains("Stock Detail"))
        XCTAssertFalse(text.contains("Qty")) // dead columns removed from the ledger-line table entirely
    }

    private func pdfText(_ data: Data) -> String {
        let document = PDFDocument(data: data)
        return (document?.string ?? "") + "\n" + ((document?.page(at: 0)?.string) ?? "")
    }
}
