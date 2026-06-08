import XCTest
@testable import Mally

final class VoucherServiceTests: XCTestCase {

    private func movement(_ db: SQLiteDatabase, account: Account.ID) throws -> (dr: Int64, cr: Int64) {
        let r = try db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr
            FROM mally_ledger_lines WHERE account_id = ?
            """,
            bind: [.text(account.uuidString)]
        ) { ($0.int("dr"), $0.int("cr")) }
        return (r?.0 ?? 0, r?.1 ?? 0)
    }

    func testBalancedPostPersistsWithEqualDebitCredit() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let draft = tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ])
        let result = try svc.post(draft: draft, in: tc.fy)
        XCTAssertEqual(result.voucher.totalPaise, 50000)

        // Whole-book invariant: total debits == total credits.
        let totals = try tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr
            FROM mally_ledger_lines
            """
        ) { ($0.int("dr"), $0.int("cr")) }
        XCTAssertEqual(totals?.0, totals?.1)
    }

    func testUnbalancedPostThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let draft = tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 40000, .credit)
        ])
        XCTAssertThrowsError(try svc.post(draft: draft, in: tc.fy)) { error in
            guard case AppError.validation(let ve) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(ve.code, .voucherDebitCreditMismatch)
        }
    }

    func testReverseNetsAccountsToZeroMovement() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        _ = try svc.reverse(posted.voucher.id, reason: "test reversal")

        let cash = try movement(tc.db, account: tc.cashId)
        let sales = try movement(tc.db, account: tc.salesId)
        // After reversal each account's signed movement nets to zero.
        XCTAssertEqual(cash.dr - cash.cr, 0)
        XCTAssertEqual(sales.dr - sales.cr, 0)
    }

    func testPostMarksAccountsUsed() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let repo = AccountRepository(db: tc.db)
        XCTAssertNotNil(try repo.findById(tc.cashId)?.lastUsedAt)
        XCTAssertNotNil(try repo.findById(tc.salesId)?.lastUsedAt)
    }

    func testEditInLockedFinancialYearThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherFYLocked)
        }
    }

    func testPostInLockedFinancialYearThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherFYLocked)
        }
    }

    func testLockedYearVoucherCanReverseIntoLatestOpenYear() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(nextFY)

        let reversal = try svc.reverse(posted.voucher.id, reason: "lock correction")
        XCTAssertEqual(reversal.financialYearId, nextFY.id)
        XCTAssertEqual(reversal.reversalOfId, posted.voucher.id)
    }

    func testVoucherCannotBeReversedTwice() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        _ = try svc.reverse(posted.voucher.id, reason: "first")

        XCTAssertThrowsError(try svc.reverse(posted.voucher.id, reason: "second")) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected business rule, got \(error)")
            }
            XCTAssertTrue(message.contains("already been reversed"))
        }
    }

    func testVoucherDeleteDoesNotCascadeLedgerLinesSilently() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let beforeDeleteCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_ledger_lines WHERE voucher_id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(beforeDeleteCount, 2)

        XCTAssertThrowsError(try tc.db.execute(
            "DELETE FROM mally_vouchers WHERE id = ?",
            [.text(posted.voucher.id.uuidString)]
        )) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(
                sqliteError.message.localizedCaseInsensitiveContains("foreign key"),
                "Expected foreign-key protection, got \(sqliteError.message)"
            )
        }

        let voucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_vouchers WHERE id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(voucherCount, 1)

        let afterDeleteCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_ledger_lines WHERE voucher_id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(afterDeleteCount, 2)
    }

    func testMarkUsedThrowsWhenAccountMissing() throws {
        let tc = try TestCompany.make()
        let missingId = UUID()

        XCTAssertThrowsError(try AccountRepository(db: tc.db).markUsed(missingId)) { error in
            guard case AppError.notFound(let message) = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(message, "Account not found for usage update")
        }
    }

    func testVoucherPostRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure
            BEFORE UPDATE OF last_used_at ON mally_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced markUsed failure"))
        }

        let voucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_vouchers",
            row: { $0.int(0) }
        )
        XCTAssertEqual(voucherCount, 0)

        let lineCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_ledger_lines",
            row: { $0.int(0) }
        )
        XCTAssertEqual(lineCount, 0)
    }

    func testVoucherEditRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Original", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure_on_edit
            BEFORE UPDATE OF last_used_at ON mally_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced edit markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", narration: "Edited", lines: [
            tc.line(tc.cashId, 60000, .debit),
            tc.line(tc.salesId, 60000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced edit markUsed failure"))
        }

        let storedVoucher = try XCTUnwrap(svc.findById(posted.voucher.id))
        XCTAssertEqual(storedVoucher.date, DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(storedVoucher.narration, "Original")
        XCTAssertEqual(storedVoucher.totalPaise, 50000)

        let storedLines = try svc.lines(for: posted.voucher.id)
        XCTAssertEqual(storedLines.count, 2)
        XCTAssertEqual(storedLines.map(\.amountPaise), [50000, 50000])

        let editAuditCount = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .voucherEdited)
        ).count
        XCTAssertEqual(editAuditCount, 0)
    }

    func testVoucherReverseRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Original", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure_on_reverse
            BEFORE UPDATE OF last_used_at ON mally_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced reverse markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.reverse(posted.voucher.id, reason: "cleanup")) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced reverse markUsed failure"))
        }

        let reversalCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_vouchers WHERE reversal_of_id = ? AND is_reversal = 1",
            bind: [.text(posted.voucher.id.uuidString)],
            row: { $0.int(0) }
        )
        XCTAssertEqual(reversalCount, 0)

        let reverseAuditCount = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .voucherReversed)
        ).count
        XCTAssertEqual(reverseAuditCount, 0)

        let totalVoucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_vouchers",
            row: { $0.int(0) }
        )
        XCTAssertEqual(totalVoucherCount, 1)
    }
}
