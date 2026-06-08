import XCTest
@testable import Mally

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
            assertInvalidUUID(error, field: "mally_accounts.id", raw: "bad-account-id")
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
            assertInvalidUUID(error, field: "mally_financial_years.company_id", raw: "bad-company-id")
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
            assertInvalidUUID(error, field: "mally_vouchers.party_account_id", raw: "bad-party-id")
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
            assertInvalidUUID(error, field: "mally_ledger_lines.voucher_id", raw: "bad-voucher-id")
        }
    }

    func testRegistryRepositoryRejectsMalformedRegistryId() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        try db.execute(
            """
            INSERT INTO mally_registry_companies
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
            assertInvalidUUID(error, field: "mally_registry_companies.id", raw: "bad-registry-id")
        }
    }

    func testDayBookRejectsMalformedVoucherId() throws {
        let tc = try TestCompany.make()
        let badId = "bad-day-book-voucher-id"
        try tc.db.execute(
            """
            INSERT INTO mally_vouchers
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

    private func assertInvalidUUID(_ error: Error, field: String, raw: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case AppError.database(.rowReadFailed(let message)) = error else {
            return XCTFail("Expected rowReadFailed, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(message, "Invalid UUID in \(field): \(raw)", file: file, line: line)
    }
}
