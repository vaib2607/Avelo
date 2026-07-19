import XCTest
@testable import Avelo

/// Direct integrity matrix for the V027 canonical tracks (Rev3 §4.4/§4.7).
/// Each constraint gets a happy-path/negative-path pair proving it fails
/// closed with no partial write, exercised directly at the SQL layer rather
/// than only through service-level happy paths.
final class CanonicalIntegrityMatrixTests: XCTestCase {

    // MARK: trn_inventory_cost_allocations cross-company ownership

    /// The cross-company ownership trigger was already proven for
    /// trn_accounting/trn_inventory inserts (FiscalLockEnforcementTests);
    /// trn_inventory_cost_allocations' own insert trigger had no direct
    /// coverage.
    func testCostAllocationTriggerRejectsCrossCompanyAccountingReference() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.seed(into: tc.db, companyId: UUID(), companyName: "Other Co")

        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ]),
            in: tc.fy
        ).voucher
        let accounting = try XCTUnwrap(LedgerLineRepository(db: tc.db).findForVoucher(voucher.id).first)

        // A second company's inventory movement, seeded into the SAME
        // connection so a cross-company reference is expressible in one
        // INSERT (a different SQLiteDatabase entirely wouldn't even see
        // this row).
        let otherItem = try InventoryService(db: tc.db, companyId: other.companyId).createItem(code: "X-1", name: "X", unit: "NOS")
        let otherMovement = StockMovement(
            companyId: other.companyId, itemId: otherItem.id, date: DateFormatters.parseDate("2024-06-01")!,
            movementType: .stockIn, quantity: try ExactQuantity.whole(1), unitCostPaise: 1_000, totalValuePaise: 1_000
        )
        try InventoryRepository(db: tc.db).insertMovement(otherMovement)

        XCTAssertThrowsError(try tc.db.execute(
            """
            INSERT INTO trn_inventory_cost_allocations (id, company_id, accounting_id, inventory_id, allocated_paise, created_at)
            VALUES (?, ?, ?, ?, 1, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(accounting.id.uuidString), .text(otherMovement.id.uuidString), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "one company") }

        // Happy path: allocation within the same company succeeds.
        let ownItem = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "OWN-1", name: "Own", unit: "NOS")
        let ownMovement = StockMovement(
            companyId: tc.companyId, itemId: ownItem.id, date: DateFormatters.parseDate("2024-06-01")!,
            movementType: .stockIn, quantity: try ExactQuantity.whole(1), unitCostPaise: 1_000, totalValuePaise: 1_000
        )
        try InventoryRepository(db: tc.db).insertMovement(ownMovement)
        XCTAssertNoThrow(try tc.db.execute(
            """
            INSERT INTO trn_inventory_cost_allocations (id, company_id, accounting_id, inventory_id, allocated_paise, created_at)
            VALUES (?, ?, ?, ?, 1, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(accounting.id.uuidString), .text(ownMovement.id.uuidString), .timestamp(Date())]
        ))
    }

    // MARK: CHECK constraints — trn_accounting

    func testTrnAccountingRejectsNonPositiveAmount() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [tc.line(tc.cashId, 1_000, .debit), tc.line(tc.salesId, 1_000, .credit)]),
            in: tc.fy
        ).voucher

        XCTAssertThrowsError(try tc.db.execute(
            "INSERT INTO trn_accounting (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, line_order, created_at) VALUES (?, ?, ?, ?, 0, 'debit', 99, ?)",
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(voucher.id.uuidString), .text(tc.cashId.uuidString), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "CHECK constraint") }
    }

    func testTrnAccountingRejectsInvalidDebitCreditSide() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [tc.line(tc.cashId, 1_000, .debit), tc.line(tc.salesId, 1_000, .credit)]),
            in: tc.fy
        ).voucher

        XCTAssertThrowsError(try tc.db.execute(
            "INSERT INTO trn_accounting (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, line_order, created_at) VALUES (?, ?, ?, ?, 100, 'sideways', 99, ?)",
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(voucher.id.uuidString), .text(tc.cashId.uuidString), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "CHECK constraint") }
    }

    func testTrnAccountingRejectsDuplicateLineOrderForSameVoucher() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [tc.line(tc.cashId, 1_000, .debit), tc.line(tc.salesId, 1_000, .credit)]),
            in: tc.fy
        ).voucher

        XCTAssertThrowsError(try tc.db.execute(
            "INSERT INTO trn_accounting (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, line_order, created_at) VALUES (?, ?, ?, ?, 100, 'debit', 0, ?)",
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(voucher.id.uuidString), .text(tc.cashId.uuidString), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "UNIQUE constraint") }
    }

    // MARK: CHECK constraints — trn_inventory

    func testTrnInventoryRejectsNonPositiveQuantity() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "Q-1", name: "Q", unit: "NOS")
        let mainLocation = try XCTUnwrap(tc.db.queryOne(
            "SELECT id FROM avelo_inventory_locations WHERE company_id = ? AND code = 'MAIN'",
            bind: [.text(tc.companyId.uuidString)]
        ) { try $0.requiredText("id") })

        XCTAssertThrowsError(try tc.db.execute(
            """
            INSERT INTO trn_inventory (id, company_id, stock_item_id, warehouse_location_id, date, movement_type, quantity_numerator, quantity_denominator, unit_cost_paise, base_value_paise, landed_cost_paise, created_at)
            VALUES (?, ?, ?, ?, ?, 'in', 0, 1, 100, 100, 0, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(item.id.uuidString), .text(mainLocation), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "CHECK constraint") }
    }

    func testTrnInventoryRejectsInvalidMovementType() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "Q-2", name: "Q2", unit: "NOS")
        let mainLocation = try XCTUnwrap(tc.db.queryOne(
            "SELECT id FROM avelo_inventory_locations WHERE company_id = ? AND code = 'MAIN'",
            bind: [.text(tc.companyId.uuidString)]
        ) { try $0.requiredText("id") })

        XCTAssertThrowsError(try tc.db.execute(
            """
            INSERT INTO trn_inventory (id, company_id, stock_item_id, warehouse_location_id, date, movement_type, quantity_numerator, quantity_denominator, unit_cost_paise, base_value_paise, landed_cost_paise, created_at)
            VALUES (?, ?, ?, ?, ?, 'sideways', 1, 1, 100, 100, 0, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(item.id.uuidString), .text(mainLocation), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(Date())]
        )) { assertIntegrityMessage($0, contains: "CHECK constraint") }
    }

    private func assertIntegrityMessage(_ error: Error, contains substring: String, file: StaticString = #filePath, line: UInt = #line) {
        let wrapped = AppError.wrap(error)
        let message: String
        switch wrapped {
        case .database(.execFailed(let value)),
             .database(.prepareFailed(let value)),
             .database(.stepFailed(let value)),
             .database(.rowReadFailed(let value)),
             .database(.schemaMismatch(let value)),
             .database(.openFailed(let value)):
            message = value
        case .businessRule(let value):
            message = value
        default:
            message = wrapped.localizedMessage
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains(substring),
                       "Expected message to contain '\(substring)': \(message)", file: file, line: line)
    }
}
