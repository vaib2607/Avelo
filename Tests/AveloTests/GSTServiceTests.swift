import XCTest
@testable import Avelo

/// AVL-P0-022: `voucherTaxBreakdown` is the per-voucher CGST/SGST/IGST/CESS
/// split that `InvoicePDFService` renders on a tax invoice.
final class GSTServiceTests: XCTestCase {

    func testGSTExportAuditsOnlyAfterSuccessfulFileSave() throws {
        let tc = try TestCompany.make()
        let service = GSTService(db: tc.db, companyId: tc.companyId)
        let from = DateFormatters.parseDate("2024-04-01")!
        let to = DateFormatters.parseDate("2024-06-30")!
        let data = try service.exportGSTSummaryCSV(fromDate: from, toDate: to)
        XCTAssertEqual(try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .gstReportExported)).count, 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gst-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        try service.recordExportSaved(kind: "gst_summary_export", fromDate: from, toDate: to, url: url)

        let events = try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .gstReportExported))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.entityId, url.lastPathComponent)
    }

    func testGSTSavedArtifactIsRemovedWhenExportAuditFails() throws {
        let tc = try TestCompany.make()
        let service = GSTService(db: tc.db, companyId: tc.companyId)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gst-fail-\(UUID().uuidString).csv")
        try Data("test".utf8).write(to: url)
        try tc.db.execute(
            "CREATE TRIGGER trg_test_fail_gst_export_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'gstReportExported' BEGIN SELECT RAISE(ABORT, 'forced export audit failure'); END;"
        )

        XCTAssertThrowsError(try service.recordExportSaved(
            kind: "gst_summary_export",
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-06-30")!,
            url: url
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testVoucherTaxBreakdownReadsCgstSgstFromPostedLines() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: tc.customerId,
            lines: [
                .init(accountId: tc.customerId, amountPaise: 11800, side: .debit),
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
            partyAccountId: tc.customerId,
            lines: [
                .init(accountId: tc.customerId, amountPaise: 11800, side: .debit),
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
            partyAccountId: tc.customerId,
            lines: [
                .init(accountId: tc.customerId, amountPaise: 10000, side: .debit),
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
