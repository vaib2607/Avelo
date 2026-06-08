import XCTest
@testable import Avelo

final class AuditCoverageTests: XCTestCase {

    func testVoucherLifecycleWritesAuditEvents() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)
        let postedAudit = try XCTUnwrap(
            AuditRepository(db: tc.db).list(
                filter: .init(companyId: tc.companyId, action: .voucherPosted)
            ).first
        )
        XCTAssertEqual(postedAudit.entityId, posted.voucher.id.uuidString)
        XCTAssertNotNil(postedAudit.snapshotAfterJson)

        _ = try service.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", narration: "Edited", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)
        let editedAudit = try XCTUnwrap(
            AuditRepository(db: tc.db).list(
                filter: .init(companyId: tc.companyId, action: .voucherEdited)
            ).first
        )
        XCTAssertEqual(editedAudit.entityId, posted.voucher.id.uuidString)
        XCTAssertNotNil(editedAudit.snapshotBeforeJson)
        XCTAssertNotNil(editedAudit.snapshotAfterJson)

        let reversed = try service.reverse(posted.voucher.id, reason: "cleanup")
        let reversedAudit = try XCTUnwrap(
            AuditRepository(db: tc.db).list(
                filter: .init(companyId: tc.companyId, action: .voucherReversed)
            ).first
        )
        XCTAssertEqual(reversedAudit.entityId, reversed.id.uuidString)
        XCTAssertEqual(reversedAudit.reason, "cleanup")
        XCTAssertNotNil(reversedAudit.snapshotBeforeJson)
        XCTAssertNotNil(reversedAudit.snapshotAfterJson)
    }
}
