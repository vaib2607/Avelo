import XCTest
@testable import Avelo

final class CompanyIsolationTests: XCTestCase {

    func testVoucherListIsScopedToCompany() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")

        let serviceA = VoucherService(db: db, companyId: companyA.companyId)
        let serviceB = VoucherService(db: db, companyId: companyB.companyId)

        let voucherA = try serviceA.post(draft: companyA.draft(on: "2024-06-01", lines: [
            companyA.line(companyA.cashId, 50000, .debit),
            companyA.line(companyA.salesId, 50000, .credit)
        ]), in: companyA.fy)

        _ = try serviceB.post(draft: companyB.draft(on: "2024-06-01", lines: [
            companyB.line(companyB.cashId, 70000, .debit),
            companyB.line(companyB.salesId, 70000, .credit)
        ]), in: companyB.fy)

        let listedByA = try serviceA.list(filter: .init(companyId: companyA.companyId))
        XCTAssertEqual(listedByA.map(\.id), [voucherA.voucher.id])
    }

    func testVoucherPostRejectsForeignCompanyAccount() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let serviceA = VoucherService(db: db, companyId: companyA.companyId)

        XCTAssertThrowsError(try serviceA.post(draft: companyA.draft(on: "2024-06-01", lines: [
            companyA.line(companyA.cashId, 50000, .debit),
            companyA.line(companyB.salesId, 50000, .credit)
        ]), in: companyA.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
        }
    }
<<<<<<< HEAD

    func testVoucherInsertTriggerRejectsForeignFinancialYear() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")

        XCTAssertThrowsError(
            try db.execute(
                """
                INSERT INTO avelo_vouchers
                (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
                 narration, status, is_reversal, reversal_of_id, cancelled_at, cancelled_by, cancellation_reason,
                 cancellation_voucher_id, is_posted, total_paise, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', 0, NULL, NULL, NULL, NULL, NULL, 1, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(companyA.companyId.uuidString),
                    .text(companyB.fy.id.uuidString),
                    .text(VoucherType.Code.journal.rawValue),
                    .text("JV-FOREIGN-FY"),
                    .date(DateFormatters.parseDate("2024-06-01")!),
                    .optionalText(companyA.cashId.uuidString),
                    .text("Foreign FY"),
                    .integer(10_000),
                    .timestamp(Date()),
                    .timestamp(Date())
                ]
            )
        ) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.localizedCaseInsensitiveContains("same company"))
        }
    }

    func testLedgerLineInsertTriggerRejectsForeignAccountOnLocalVoucher() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let posted = try VoucherService(db: db, companyId: companyA.companyId).post(
            draft: companyA.draft(on: "2024-06-01", lines: [
                companyA.line(companyA.cashId, 50_000, .debit),
                companyA.line(companyA.salesId, 50_000, .credit)
            ]),
            in: companyA.fy
        )

        XCTAssertThrowsError(
            try db.execute(
                """
                INSERT INTO avelo_ledger_lines
                (id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(companyA.companyId.uuidString),
                    .text(posted.voucher.id.uuidString),
                    .text(companyB.salesId.uuidString),
                    .integer(1_000),
                    .text(EntrySide.debit.rawValue),
                    .null,
                    .null,
                    .integer(9)
                ]
            )
        ) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.localizedCaseInsensitiveContains("same company"))
        }
    }

    func testStockMovementInsertTriggerRejectsForeignCompanyItem() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let foreignItem = try InventoryService(db: db, companyId: companyB.companyId)
            .createItem(code: "FOREIGN-ITEM", name: "Foreign Item", unit: "NOS")

        XCTAssertThrowsError(
            try InventoryRepository(db: db).insertMovement(
                StockMovement(
                    companyId: companyA.companyId,
                    itemId: foreignItem.id,
                    date: DateFormatters.parseDate("2024-06-01")!,
                    movementType: .stockIn,
                    quantity: 1,
                    unitCostPaise: 100,
                    totalValuePaise: 100
                )
            )
        ) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.localizedCaseInsensitiveContains("same company"))
        }
    }

    func testPayrollServiceRejectsForeignEmployeeAndForeignFinancialYear() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let employeeB = try PayrollService(db: db, companyId: companyB.companyId).createEmployee(
            name: "Foreign Employee",
            employeeCode: "EMP-B",
            designation: nil,
            pan: nil,
            baseSalaryPaise: 50_000_00
        )
        let serviceA = PayrollService(db: db, companyId: companyA.companyId)

        XCTAssertThrowsError(
            try serviceA.postEntry(
                employeeId: employeeB.id,
                monthYear: 202406,
                deductionsPaise: 0,
                financialYearId: companyB.fy.id,
                salaryExpenseAccountId: companyA.rentId,
                paymentAccountId: companyA.cashId
            )
        ) { error in
            guard case AppError.notFound(let entity) = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(entity, "Employee")
        }
    }

    func testBankImportRejectsForeignCompanyAccount() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let serviceA = BankReconciliationService(db: db, companyId: companyA.companyId)

        XCTAssertThrowsError(
            try serviceA.importStatement(
                accountId: companyB.cashId,
                entries: [
                    .init(
                        id: UUID(),
                        companyId: companyB.companyId,
                        accountId: companyB.cashId,
                        date: DateFormatters.parseDate("2024-06-03")!,
                        amountPaise: -1_000,
                        narration: "Foreign bank row",
                        isCleared: false
                    )
                ]
            )
        ) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
            XCTAssertTrue(validation.message.localizedCaseInsensitiveContains("another company"))
        }
    }
=======
>>>>>>> origin/main
}
