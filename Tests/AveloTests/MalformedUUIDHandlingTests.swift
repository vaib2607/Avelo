import XCTest
@testable import Avelo

final class MalformedUUIDHandlingTests: XCTestCase {

    func testAccountRowDecoderRejectsMalformedAccountId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT 'bad-account-id' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS group_id,
                   '1001' AS code,
                   'Cash' AS name,
                   0 AS opening_balance_paise,
                   'debit' AS opening_balance_side,
                    1 AS is_active,
                   0 AS is_bank_account,
                   NULL AS gstin,
                   NULL AS last_used_at,
                   '2024-04-01T00:00:00Z' AS created_at,
                   '2024-04-01T00:00:00Z' AS updated_at
            """
        ) { try AccountRepository.rowToAccount($0) }) { error in
            assertInvalidUUID(error, field: "avelo_accounts.id", raw: "bad-account-id")
        }
    }

    func testFinancialYearRowDecoderRejectsMalformedCompanyId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   'bad-company-id' AS company_id,
                   '2024-25' AS label,
                   '2024-04-01' AS start_date,
                   '2025-03-31' AS end_date,
                   '2024-04-01' AS books_begin_date,
                   0 AS is_locked,
                   NULL AS is_closed,
                    '2024-04-01T00:00:00Z' AS created_at
            """
        ) { try FinancialYearRepository.rowToFinancialYear($0) }) { error in
            assertInvalidUUID(error, field: "avelo_financial_years.company_id", raw: "bad-company-id")
        }
    }

    func testVoucherRowDecoderRejectsMalformedOptionalPartyAccountId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS financial_year_id,
                   'JV-0001' AS number,
                   '2024-06-01' AS date,
                   'journal' AS voucher_type_code,
                   'Test voucher' AS narration,
                   'bad-party-id' AS party_account_id,
                   NULL AS gst_treatment,
                   NULL AS source_voucher_id,
                   NULL AS source_action,
                   0 AS is_reversal,
                   NULL AS reversal_of_id,
                   50000 AS total_paise,
                   '2024-06-01T00:00:00Z' AS created_at,
                   '2024-06-01T00:00:00Z' AS updated_at
            """
        ) { try VoucherRepository.rowToVoucher($0) }) { error in
            assertInvalidUUID(error, field: "avelo_vouchers.party_account_id", raw: "bad-party-id")
        }
    }

    func testLedgerLineRowDecoderRejectsMalformedVoucherId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   'bad-voucher-id' AS voucher_id,
                   '\(UUID().uuidString)' AS account_id,
                   1000 AS amount_paise,
                   'debit' AS side,
                   0 AS line_order,
                   'line' AS narration
            """
        ) { try LedgerLineRepository.rowToLine($0) }) { error in
            assertInvalidUUID(error, field: "avelo_ledger_lines.voucher_id", raw: "bad-voucher-id")
        }
    }

    func testRegistryRepositoryRejectsMalformedRegistryId() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        try db.execute(
            """
            INSERT INTO avelo_registry_companies
            (id, name, sqlite_file_name, last_opened_at, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text("bad-registry-id"),
                .text("Broken Co"),
                .text("broken.sqlite"),
                .null,
                .text("2024-06-01T00:00:00Z")
            ]
        )

        XCTAssertThrowsError(try RegistryRepository(db: db).listCompanies()) { error in
            assertInvalidUUID(error, field: "avelo_registry_companies.id", raw: "bad-registry-id")
        }
    }

    func testDayBookRejectsMalformedVoucherId() throws {
        let tc = try TestCompany.make()
        let badId = "bad-day-book-voucher-id"
        try tc.db.execute(
            """
            INSERT INTO avelo_vouchers
            (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
             narration, is_reversal, reversal_of_id, is_posted, total_paise, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(badId),
                .text(tc.companyId.uuidString),
                .text(tc.fy.id.uuidString),
                .text(VoucherType.Code.journal.rawValue),
                .text("JV-BAD"),
                .date(DateFormatters.parseDate("2024-06-01")!),
                .null,
                .text("Malformed ID"),
                .bool(false),
                .null,
                .bool(true),
                .integer(1000),
                .text("2024-06-01T00:00:00Z"),
                .text("2024-06-01T00:00:00Z")
            ]
        )

        XCTAssertThrowsError(try ReportRepository(db: tc.db).dayBook(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2025-03-31")!,
            filter: .init(companyId: tc.companyId)
        )) { error in
            assertInvalidUUID(error, field: "report.day_book.voucher_id", raw: badId)
        }
    }

    func testStockMovementDecoderRejectsMalformedVoucherId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS item_id,
                   'bad-voucher-id' AS voucher_id,
                   '2024-04-01' AS date,
                   'in' AS movement_type,
                   1 AS quantity,
                   1000 AS unit_cost_paise,
                   1000 AS total_value_paise,
                   NULL AS reference_voucher_number,
                   NULL AS reason,
                   '2024-04-01T00:00:00Z' AS created_at
            """
        ) { try InventoryRepository.rowToMovement($0) }) { error in
            assertInvalidUUID(error, field: "avelo_stock_movements.voucher_id", raw: "bad-voucher-id")
        }
    }

    func testPayrollEntryDecoderRejectsMalformedFinancialYearId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS employee_id,
                   'bad-fy-id' AS financial_year_id,
                   NULL AS voucher_id,
                   4 AS month,
                   2024 AS year,
                   10000 AS gross_paise,
                   0 AS deductions_paise,
                   10000 AS net_paise,
                   '2024-04-01T00:00:00Z' AS posted_at
            """
        ) { try PayrollRepository.rowToEntry($0) }) { error in
            assertInvalidUUID(error, field: "avelo_payroll_entries.financial_year_id", raw: "bad-fy-id")
        }
    }

    func testBankReconciliationDecoderRejectsMalformedAccountId() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   'bad-bank-account-id' AS bank_account_id,
                   '\(UUID().uuidString)' AS voucher_id,
                   '2024-04-01' AS statement_date,
                   10000 AS statement_amount_paise,
                   0 AS is_cleared,
                   NULL AS cleared_at,
                   NULL AS note
            """
        ) { r in
            BankReconciliationRepository.Entry(
                id: try UUIDParsing.required(r.text("id"), field: "avelo_bank_reconciliations.id"),
                companyId: try UUIDParsing.required(r.text("company_id"), field: "avelo_bank_reconciliations.company_id"),
                bankAccountId: try UUIDParsing.required(r.text("bank_account_id"), field: "avelo_bank_reconciliations.bank_account_id"),
                voucherId: try UUIDParsing.required(r.text("voucher_id"), field: "avelo_bank_reconciliations.voucher_id"),
                statementDate: r.date("statement_date"),
                statementAmountPaise: r.int("statement_amount_paise"),
                isCleared: r.bool("is_cleared"),
                clearedAt: nil,
                note: r.optionalText("note")
            )
        }) { error in
            assertInvalidUUID(error, field: "avelo_bank_reconciliations.bank_account_id", raw: "bad-bank-account-id")
        }
    }

    func testVoucherRowDecoderRejectsUnknownVoucherTypeCode() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS financial_year_id,
                   'not-a-voucher-type' AS voucher_type_code,
                   'JV-0001' AS number,
                   '2024-06-01' AS date,
                   NULL AS party_account_id,
                   'Test voucher' AS narration,
                   'open' AS status,
                   0 AS is_reversal,
                   NULL AS reversal_of_id,
                   NULL AS cancelled_at,
                   NULL AS cancelled_by,
                   NULL AS cancellation_reason,
                   NULL AS cancellation_voucher_id,
                   1 AS is_posted,
                   50000 AS total_paise,
                   '2024-06-01T00:00:00Z' AS created_at,
                   '2024-06-01T00:00:00Z' AS updated_at
            """
        ) { try VoucherRepository.rowToVoucher($0) }) { error in
            assertRowRead(error, equals: "invalid Code value for column voucher_type_code: not-a-voucher-type")
        }
    }

    func testFinancialYearRowDecoderRejectsMalformedDateInsteadOfEpochFallback() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '2024-25' AS label,
                   'not-a-date' AS start_date,
                   '2025-03-31' AS end_date,
                   '2024-04-01' AS books_begin_date,
                   0 AS is_locked,
                   0 AS is_closed,
                   '2024-04-01T00:00:00Z' AS created_at
            """
        ) { try FinancialYearRepository.rowToFinancialYear($0) }) { error in
            assertRowRead(error, equals: "invalid date value for column start_date")
        }
    }

    func testVoucherRowDecoderRejectsInvalidBooleanInsteadOfCoercingTruthy() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS financial_year_id,
                   'journal' AS voucher_type_code,
                   'JV-0001' AS number,
                   '2024-06-01' AS date,
                   NULL AS party_account_id,
                   'Test voucher' AS narration,
                   'open' AS status,
                   2 AS is_reversal,
                   NULL AS reversal_of_id,
                   NULL AS cancelled_at,
                   NULL AS cancelled_by,
                   NULL AS cancellation_reason,
                   NULL AS cancellation_voucher_id,
                   1 AS is_posted,
                   50000 AS total_paise,
                   '2024-06-01T00:00:00Z' AS created_at,
                   '2024-06-01T00:00:00Z' AS updated_at
            """
        ) { try VoucherRepository.rowToVoucher($0) }) { error in
            assertRowRead(error, equals: "invalid boolean value for column is_reversal: 2")
        }
    }

    func testVoucherRowDecoderRejectsMissingRequiredColumn() throws {
        let db = try SQLiteDatabase(path: ":memory:")

        XCTAssertThrowsError(try db.queryOne(
            """
            SELECT '\(UUID().uuidString)' AS id,
                   '\(UUID().uuidString)' AS company_id,
                   '\(UUID().uuidString)' AS financial_year_id,
                   'journal' AS voucher_type_code,
                   'JV-0001' AS number,
                   '2024-06-01' AS date,
                   NULL AS party_account_id,
                   'Test voucher' AS narration,
                   0 AS is_reversal,
                   NULL AS reversal_of_id,
                   NULL AS cancelled_at,
                   NULL AS cancelled_by,
                   NULL AS cancellation_reason,
                   NULL AS cancellation_voucher_id,
                   1 AS is_posted,
                   50000 AS total_paise,
                   '2024-06-01T00:00:00Z' AS created_at,
                   '2024-06-01T00:00:00Z' AS updated_at
            """
        ) { try VoucherRepository.rowToVoucher($0) }) { error in
            assertRowRead(error, equals: "missing required column status")
        }
    }

    func testRegistryRepositoryRejectsMalformedLastOpenedTimestamp() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        try db.execute(
            """
            INSERT INTO avelo_registry_companies
            (id, name, sqlite_file_name, last_opened_at, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(UUID().uuidString),
                .text("Broken Co"),
                .text("broken.sqlite"),
                .text("not-a-timestamp"),
                .text("2024-06-01T00:00:00Z")
            ]
        )

        XCTAssertThrowsError(try RegistryRepository(db: db).listCompanies()) { error in
            assertRowRead(error, equals: "invalid timestamp value for column last_opened_at")
        }
    }

    private func assertInvalidUUID(_ error: Error, field: String, raw: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case AppError.database(.rowReadFailed(let message)) = error else {
            return XCTFail("Expected rowReadFailed, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(message, "Invalid UUID in \(field): \(raw)", file: file, line: line)
    }

    private func assertRowRead(_ error: Error, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case AppError.database(.rowReadFailed(let message)) = error else {
            return XCTFail("Expected rowReadFailed, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(message, expected, file: file, line: line)
    }
}
