import XCTest
@testable import Avelo

/// AVL-P0-022: `voucherTaxBreakdown` is the per-voucher CGST/SGST/IGST/CESS
/// split that `InvoicePDFService` renders on a tax invoice.
final class GSTServiceTests: XCTestCase {

    func testVoucherTaxBreakdownReadsCgstSgstFromPostedLines() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: tc.capitalId,
            lines: [
                .init(accountId: tc.capitalId, amountPaise: 11800, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 10000, side: .credit),
                .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
            ]
        ), in: tc.fy).voucher

        let breakdown = try GSTService(db: tc.db, companyId: tc.companyId).voucherTaxBreakdown(voucherId: voucher.id)

        XCTAssertEqual(breakdown.taxableValuePaise, 10000)
        XCTAssertEqual(breakdown.cgstPaise, 900)
        XCTAssertEqual(breakdown.sgstPaise, 900)
        XCTAssertEqual(breakdown.igstPaise, 0)
        XCTAssertEqual(breakdown.cessPaise, 0)
    }

    func testVoucherTaxBreakdownReadsIgstFromPostedLines() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: tc.capitalId,
            lines: [
                .init(accountId: tc.capitalId, amountPaise: 11800, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 10000, side: .credit),
                .init(accountId: tc.igstOutputId, amountPaise: 1800, side: .credit)
            ]
        ), in: tc.fy).voucher

        let breakdown = try GSTService(db: tc.db, companyId: tc.companyId).voucherTaxBreakdown(voucherId: voucher.id)

        XCTAssertEqual(breakdown.taxableValuePaise, 10000)
        XCTAssertEqual(breakdown.igstPaise, 1800)
        XCTAssertEqual(breakdown.cgstPaise, 0)
        XCTAssertEqual(breakdown.sgstPaise, 0)
    }

    func testVoucherTaxBreakdownIsAllZeroForAVoucherWithNoTaxLines() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: tc.capitalId,
            lines: [
                .init(accountId: tc.capitalId, amountPaise: 10000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 10000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let breakdown = try GSTService(db: tc.db, companyId: tc.companyId).voucherTaxBreakdown(voucherId: voucher.id)

        XCTAssertEqual(breakdown.taxableValuePaise, 10000)
        XCTAssertEqual(breakdown.igstPaise, 0)
        XCTAssertEqual(breakdown.cgstPaise, 0)
        XCTAssertEqual(breakdown.sgstPaise, 0)
        XCTAssertEqual(breakdown.cessPaise, 0)
    }

    func testVoucherTaxBreakdownForNonexistentVoucherIsAllZero() throws {
        let tc = try TestCompany.make()
        let breakdown = try GSTService(db: tc.db, companyId: tc.companyId).voucherTaxBreakdown(voucherId: UUID())
        XCTAssertEqual(breakdown.taxableValuePaise, 0)
        XCTAssertEqual(breakdown.igstPaise, 0)
    }
}
