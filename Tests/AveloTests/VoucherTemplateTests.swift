import XCTest
@testable import Avelo

final class VoucherTemplateTests: XCTestCase {
    func testTemplateRoundTrip() throws {
        let tc = try TestCompany.make()
        let draft = VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-06-01")!, lines: [
            .init(accountId: tc.cashId, amountPaise: 5000, side: .debit, lineOrder: 0),
            .init(accountId: tc.salesId, amountPaise: 5000, side: .credit, lineOrder: 1)
        ])
        try VoucherTemplateService(db: tc.db, companyId: tc.companyId).save(name: "Default", draft: draft)
        let loaded = try XCTUnwrap(VoucherTemplateService(db: tc.db, companyId: tc.companyId).load(name: "Default"))
        XCTAssertEqual(loaded.voucherTypeCode, .journal)
        XCTAssertEqual(loaded.lines.count, 2)
    }

    func testMalformedTemplateJSONThrowsInsteadOfLoadingEmptyDraft() throws {
        let tc = try TestCompany.make()
        try tc.db.execute(
            """
            INSERT INTO avelo_voucher_templates
            (id, company_id, name, voucher_type_code, template_lines_json, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(UUID().uuidString),
                .text(tc.companyId.uuidString),
                .text("Broken"),
                .text(VoucherType.Code.journal.rawValue),
                .text("{not-json"),
                .bool(true),
                .timestamp(Date())
            ]
        )

        XCTAssertThrowsError(try VoucherTemplateService(db: tc.db, companyId: tc.companyId).load(name: "Broken"))
    }
}
