import XCTest
@testable import Avelo

final class FiscalLockEnforcementTests: XCTestCase {

    func testCanonicalOwnershipTriggersRejectCrossCompanyReferences() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.seed(into: tc.db, companyId: UUID(), companyName: "Other Co")
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ]),
            in: tc.fy
        ).voucher

        XCTAssertThrowsError(try tc.db.execute(
            """
            INSERT INTO trn_accounting (id, company_id, voucher_id, ledger_id, amount_paise, debit_or_credit, line_order, created_at)
            VALUES (?, ?, ?, ?, 1, 'debit', 99, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(voucher.id.uuidString), .text(other.cashId.uuidString), .timestamp(Date())]
        )) { assertDatabaseMessageContains($0, substring: "same company") }

        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "OWN-1", name: "Owned", unit: "NOS")
        let otherMain = try XCTUnwrap(tc.db.queryOne(
            "SELECT id FROM avelo_inventory_locations WHERE company_id = ? AND code = 'MAIN'",
            bind: [.text(other.companyId.uuidString)]
        ) { try $0.requiredText("id") })
        XCTAssertThrowsError(try tc.db.execute(
            """
            INSERT INTO trn_inventory (id, company_id, voucher_id, stock_item_id, warehouse_location_id, item_line_id, date, movement_type, quantity_numerator, quantity_denominator, unit_cost_paise, base_value_paise, landed_cost_paise, created_at)
            VALUES (?, ?, NULL, ?, ?, NULL, ?, 'in', 1, 1, 1, 1, 0, ?)
            """,
            [.text(UUID().uuidString), .text(tc.companyId.uuidString), .text(item.id.uuidString), .text(otherMain), .date(DateFormatters.parseDate("2024-06-01")!), .timestamp(Date())]
        )) { assertDatabaseMessageContains($0, substring: "same company") }
    }

    func testCanonicalTrackTriggersRejectLockedFinancialYearMutations() throws {
        let tc = try TestCompany.make()
        let voucher = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ]),
            in: tc.fy
        ).voucher
        let accounting = try XCTUnwrap(LedgerLineRepository(db: tc.db).findForVoucher(voucher.id).first)
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: "CAN-LOCK", name: "Canonical Lock", unit: "NOS")
        let movement = StockMovement(
            companyId: tc.companyId,
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            movementType: .stockIn,
            quantity: try ExactQuantity.whole(1),
            unitCostPaise: 1_000,
            totalValuePaise: 1_000
        )
        try InventoryRepository(db: tc.db).insertMovement(movement)
        let allocation = try InventoryCostAllocation(
            companyId: tc.companyId,
            accountingId: accounting.id,
            inventoryId: movement.id,
            allocatedPaise: 1
        )
        try InventoryCostAllocationRepository(db: tc.db).insert(allocation)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try tc.db.execute(
            "UPDATE trn_accounting SET amount_paise = amount_paise WHERE id = ?",
            [.text(accounting.id.uuidString)]
        )) { assertDatabaseMessageContains($0, substring: "Financial year is locked") }
        XCTAssertThrowsError(try tc.db.execute(
            "UPDATE trn_inventory SET reason = 'locked' WHERE id = ?",
            [.text(movement.id.uuidString)]
        )) { assertDatabaseMessageContains($0, substring: "Financial year is locked") }
        XCTAssertThrowsError(try tc.db.execute(
            "UPDATE trn_inventory_cost_allocations SET allocated_paise = allocated_paise WHERE id = ?",
            [.text(allocation.id.uuidString)]
        )) { assertDatabaseMessageContains($0, substring: "Financial year is locked") }
    }

    func testInventoryServiceRejectsStockMovementInLockedFinancialYear() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "LOCK-STOCK", name: "Locked Stock", unit: "NOS")
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(
            try service.recordMovement(
                itemId: item.id,
                date: DateFormatters.parseDate("2024-06-01")!,
                type: .stockIn,
                quantity: 1,
                ratePaise: 100
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule failure, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("locked"))
        }
    }

    func testStockMovementInsertTriggerRejectsLockedFinancialYearDate() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId)
            .createItem(code: "LOCK-SQL", name: "Locked SQL Stock", unit: "NOS")
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(
            try InventoryRepository(db: tc.db).insertMovement(
                StockMovement(
                    companyId: tc.companyId,
                    itemId: item.id,
                    date: DateFormatters.parseDate("2024-06-01")!,
                    movementType: .stockIn,
                    quantity: try ExactQuantity.whole(1),
                    unitCostPaise: 100,
                    totalValuePaise: 100
                )
            )
        ) { error in
            assertDatabaseMessageContains(error, substring: "stock movements are not allowed")
        }
    }

    func testBankStatementImportAndClearRejectLockedFinancialYear() throws {
        let tc = try TestCompany.make()
        let service = BankReconciliationService(db: tc.db, companyId: tc.companyId)
        try service.importStatement(accountId: tc.cashId, entries: [
            .init(
                id: UUID(),
                companyId: tc.companyId,
                accountId: tc.cashId,
                date: DateFormatters.parseDate("2024-06-03")!,
                amountPaise: -10_000,
                narration: "Imported before lock",
                isCleared: false
            )
        ])
        let line = try XCTUnwrap(
            BankReconciliationRepository(db: tc.db)
                .statementLines(accountId: tc.cashId, asOf: DateFormatters.parseDate("2024-06-30")!)
                .first
        )
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(
            try service.importStatement(accountId: tc.cashId, entries: [
                .init(
                    id: UUID(),
                    companyId: tc.companyId,
                    accountId: tc.cashId,
                    date: DateFormatters.parseDate("2024-06-04")!,
                    amountPaise: -2_000,
                    narration: "Blocked by lock",
                    isCleared: false
                )
            ])
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule failure, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("locked"))
        }

        XCTAssertThrowsError(try service.clearStatementLine(id: line.id)) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule failure, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("locked"))
        }
    }

    func testBankStatementUpdateTriggerRejectsLockedFinancialYearClearance() throws {
        let tc = try TestCompany.make()
        let repo = BankReconciliationRepository(db: tc.db)
        try repo.insertStatementLine(
            companyId: tc.companyId,
            accountId: tc.cashId,
            date: DateFormatters.parseDate("2024-06-03")!,
            amountPaise: -1_000,
            narration: "Locked bank line"
        )
        let line = try XCTUnwrap(repo.statementLines(accountId: tc.cashId, asOf: DateFormatters.parseDate("2024-06-30")!).first)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try repo.clearStatementLine(id: line.id)) { error in
            assertDatabaseMessageContains(error, substring: "bank statement edits are not allowed")
        }
    }

    func testPayrollEntryInsertTriggerRejectsLockedFinancialYear() throws {
        let tc = try TestCompany.make()
        let payroll = PayrollService(db: tc.db, companyId: tc.companyId)
        let employee = try payroll.createEmployee(
            name: "Locked Payroll",
            employeeCode: "EMP-LOCK",
            designation: nil,
            pan: nil,
            baseSalaryPaise: 10_000
        )
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(
            try tc.db.execute(
                """
                INSERT INTO avelo_payroll_entries
                (id, company_id, employee_id, financial_year_id, voucher_id, month, year, gross_paise, deductions_paise, net_paise, posted_at)
                VALUES (?, ?, ?, ?, NULL, 6, 2024, 10000, 0, 10000, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(tc.companyId.uuidString),
                    .text(employee.id.uuidString),
                    .text(tc.fy.id.uuidString),
                    .timestamp(Date())
                ]
            )
        ) { error in
            assertDatabaseMessageContains(error, substring: "payroll entries are not allowed")
        }
    }

    func testOpeningBalanceChangesRejectLockedFinancialYearAtServiceAndTrigger() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        var account = try XCTUnwrap(service.findAccount(tc.cashId))
        account = Account(
            id: account.id,
            companyId: account.companyId,
            groupId: account.groupId,
            code: account.code,
            name: account.name,
            openingBalancePaise: account.openingBalancePaise + 1_000,
            openingBalanceSide: account.openingBalanceSide,
            isActive: account.isActive,
            isBankAccount: account.isBankAccount,
            gstin: account.gstin,
            lastUsedAt: account.lastUsedAt,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt
        )

        XCTAssertThrowsError(try service.updateAccount(account)) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule failure, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("opening balance"))
        }

        XCTAssertThrowsError(
            try tc.db.execute(
                "UPDATE avelo_accounts SET opening_balance_paise = opening_balance_paise + 1000 WHERE id = ?",
                [.text(tc.cashId.uuidString)]
            )
        ) { error in
            assertDatabaseMessageContains(error, substring: "opening balance changes are not allowed")
        }
    }

    func testVoucherUpdateTriggersRejectOutsideFinancialYearAndLockedTargetYear() throws {
        let tc = try TestCompany.make()
        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ]),
            in: tc.fy
        ).voucher

        XCTAssertThrowsError(
            try tc.db.execute(
                "UPDATE avelo_vouchers SET date = ? WHERE id = ?",
                [.date(DateFormatters.parseDate("2026-04-01")!), .text(posted.id.uuidString)]
            )
        ) { error in
            assertDatabaseMessageContains(error, substring: "outside its financial year")
        }

        let lockedYear = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!,
            isLocked: true
        )
        try FinancialYearRepository(db: tc.db).insert(lockedYear)

        XCTAssertThrowsError(
            try tc.db.execute(
                "UPDATE avelo_vouchers SET financial_year_id = ?, date = ? WHERE id = ?",
                [
                    .text(lockedYear.id.uuidString),
                    .date(DateFormatters.parseDate("2025-06-01")!),
                    .text(posted.id.uuidString)
                ]
            )
        ) { error in
            assertDatabaseMessageContains(error, substring: "voucher edits are not allowed")
        }
    }

    private func assertDatabaseMessageContains(_ error: Error, substring: String, file: StaticString = #filePath, line: UInt = #line) {
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
            XCTFail("Expected database/business-rule error, got \(wrapped)", file: file, line: line)
            return
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains(substring), "Expected '\(message)' to contain '\(substring)'", file: file, line: line)
    }
}
