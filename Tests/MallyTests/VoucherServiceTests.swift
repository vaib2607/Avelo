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
}
