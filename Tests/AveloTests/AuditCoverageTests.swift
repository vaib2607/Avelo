import XCTest
@testable import Avelo

final class AuditCoverageTests: XCTestCase {

    func testInventoryMasterAlterAndDisablePreserveBeforeAndAfterSnapshots() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        var item = try service.createItem(code: "AUD-ITEM", name: "Before", unit: "Nos")
        item.name = "After"

        try service.updateItem(item)
        try service.archiveItem(item.id)

        let repository = AuditRepository(db: tc.db)
        let updates = try repository.list(filter: .init(companyId: tc.companyId, action: .stockItemUpdated))
        XCTAssertEqual(updates.count, 1)
        XCTAssertNotNil(updates.first?.snapshotBeforeJson)
        XCTAssertNotNil(updates.first?.snapshotAfterJson)
        let disables = try repository.list(filter: .init(companyId: tc.companyId, action: .stockItemDisabled))
        XCTAssertEqual(disables.count, 1)
        XCTAssertNotNil(disables.first?.snapshotBeforeJson)
        XCTAssertNotNil(disables.first?.snapshotAfterJson)
    }

    func testAccountGroupLifecycleWritesDedicatedAuditEvents() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        var group = try service.createGroup(code: "AUD-GRP", name: "Audit Group", nature: .assets)
        group.name = "Audit Group Updated"
        try service.updateGroup(group)
        try service.deleteGroup(group.id)

        let repository = AuditRepository(db: tc.db)
        XCTAssertEqual(try repository.list(filter: .init(companyId: tc.companyId, action: .accountGroupCreated)).count, 1)
        XCTAssertEqual(try repository.list(filter: .init(companyId: tc.companyId, action: .accountGroupUpdated)).count, 1)
        XCTAssertEqual(try repository.list(filter: .init(companyId: tc.companyId, action: .accountGroupDeleted)).count, 1)
    }

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

    func testStockMovementReversalWritesAuditEvent() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "AUD-STK", name: "Audit Stock", unit: "NOS", valuationMethod: .fifo)

        _ = try inventory.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            type: .stockIn,
            quantity: 10,
            ratePaise: 100
        )
        let issuePublication = try inventory.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-02")!,
            type: .stockOut,
            quantity: 4,
            ratePaise: 999
        )
        XCTAssertTrue(issuePublication.phase == .published)
        let originalOut = try XCTUnwrap(
            InventoryRepository(db: tc.db)
                .listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
                .last
        )

        let reversal = try inventory.reverseMovement(originalOut.id, reason: "audit undo")
        let reversedAudit = try XCTUnwrap(
            AuditRepository(db: tc.db).list(
                filter: .init(companyId: tc.companyId, action: .stockMovementReversed)
            ).first
        )
        XCTAssertEqual(reversedAudit.entityId, reversal.reversalMovement.id.uuidString)
        XCTAssertEqual(reversedAudit.reason, "audit undo")
        XCTAssertNotNil(reversedAudit.snapshotBeforeJson)
        XCTAssertNotNil(reversedAudit.snapshotAfterJson)
    }

    func testVoucherCancellationWritesAuditEvent() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let cancelled = try service.cancel(posted.voucher.id, reason: "entry voided")
        let cancelledAudit = try XCTUnwrap(
            AuditRepository(db: tc.db).list(
                filter: .init(companyId: tc.companyId, action: .voucherCancelled)
            ).first
        )
        XCTAssertEqual(cancelledAudit.entityId, cancelled.id.uuidString)
        XCTAssertEqual(cancelledAudit.reason, "entry voided")
        XCTAssertNotNil(cancelledAudit.snapshotBeforeJson)
        XCTAssertNotNil(cancelledAudit.snapshotAfterJson)
    }
}
