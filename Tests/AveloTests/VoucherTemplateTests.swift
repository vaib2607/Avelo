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
}
