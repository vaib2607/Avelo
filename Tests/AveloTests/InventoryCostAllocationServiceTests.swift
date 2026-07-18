import XCTest
@testable import Avelo

final class InventoryCostAllocationServiceTests: XCTestCase {
    func testQuantityAllocationUsesStableResidualAndOneAudit() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 100, .debit),
                tc.line(tc.salesId, 100, .credit)
            ]), in: tc.fy
        ).voucher
        let source = try XCTUnwrap(LedgerLineRepository(db: tc.db).findForVoucher(voucher.id).first)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "ALLOC-1", name: "Allocation Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 1, ratePaise: 100)
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 2, ratePaise: 100)
        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        let auditBefore = try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId)).count

        let result = try InventoryCostAllocationService(db: tc.db, companyId: tc.companyId).allocate(.init(
            accountingId: source.id, inventoryIds: movements.map(\.id), kind: .freight
        ))

        XCTAssertEqual(result.allocations.map(\.allocatedPaise), [33, 67])
        XCTAssertEqual(try InventoryRepository(db: tc.db).landedCostPaise(for: movements[0].id), 33)
        XCTAssertEqual(try InventoryRepository(db: tc.db).landedCostPaise(for: movements[1].id), 67)
        XCTAssertEqual(try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId)).count, auditBefore + 1)
    }

    func testAllocationRejectsRecoverableGSTSourceAndLeavesTargetsUntouched() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                .init(accountId: tc.cashId, amountPaise: 100, side: .debit, taxCode: "IGST"),
                tc.line(tc.salesId, 100, .credit)
            ]), in: tc.fy
        ).voucher
        let source = try XCTUnwrap(LedgerLineRepository(db: tc.db).findForVoucher(voucher.id).first)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "ALLOC-2", name: "Allocation Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 1, ratePaise: 100)
        let movement = try XCTUnwrap(InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id).first)

        XCTAssertThrowsError(try InventoryCostAllocationService(db: tc.db, companyId: tc.companyId).allocate(.init(
            accountingId: source.id, inventoryIds: [movement.id], kind: .irrecoverableTax
        ))) { error in
            guard case .validation(let validation) = AppError.wrap(error) else { return XCTFail("Expected validation, got \(error)") }
            XCTAssertEqual(validation.code, .inventoryCostSourceInvalid)
        }
        XCTAssertEqual(try InventoryRepository(db: tc.db).landedCostPaise(for: movement.id), 0)
    }

    func testAuditFailureRollsBackAllocationAndLandedValue() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 100, .debit), tc.line(tc.salesId, 100, .credit)
            ]), in: tc.fy
        ).voucher
        let source = try XCTUnwrap(LedgerLineRepository(db: tc.db).findForVoucher(voucher.id).first)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "ALLOC-ROLL", name: "Allocation rollback", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 1, ratePaise: 100)
        let movement = try XCTUnwrap(InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id).first)
        try tc.db.execute("CREATE TRIGGER test_reject_allocation_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'inventoryCostAllocated' BEGIN SELECT RAISE(ABORT, 'forced allocation audit failure'); END;")

        XCTAssertThrowsError(try InventoryCostAllocationService(db: tc.db, companyId: tc.companyId).allocate(.init(accountingId: source.id, inventoryIds: [movement.id], kind: .freight)))
        XCTAssertEqual(try tc.db.queryOne("SELECT COUNT(*) FROM trn_inventory_cost_allocations WHERE accounting_id = ?", bind: [.text(source.id.uuidString)]) { $0.int(0) }, 0)
        XCTAssertEqual(try InventoryRepository(db: tc.db).landedCostPaise(for: movement.id), 0)
    }
}
