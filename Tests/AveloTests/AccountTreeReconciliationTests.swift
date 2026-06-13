import XCTest
@testable import Avelo

/// The gate test: the in-memory `AccountTree` must agree, ledger-for-ledger,
/// with the authoritative SQL trial balance produced by `ReportService`.
/// This is the invariant that makes wiring reports to the cache (Phase B4) safe.
@MainActor
final class AccountTreeReconciliationTests: XCTestCase {

    private func seedActivity(_ tc: TestCompany) throws {
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        // Receipt-style: Dr Cash 500, Cr Sales 500
        _ = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)
        // Payment-style: Dr Rent 200, Cr Cash 200
        _ = try svc.post(draft: tc.draft(on: "2024-07-01", lines: [
            tc.line(tc.rentId, 20000, .debit),
            tc.line(tc.cashId, 20000, .credit)
        ]), in: tc.fy)
    }

    func testTreeBalancesMatchSqlTrialBalance() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        await cache.reload()
        guard let tree = cache.tree else {
            return XCTFail("Tree failed to load: \(String(describing: cache.lastError))")
        }

        let tb = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: tc.fy.endDate)

        // Every SQL trial-balance row's net (debit - credit) must equal the
        // tree ledger's signed balance for the same account.
        for row in tb.rows {
            guard let node = tree.findLedger(row.id) else {
                XCTFail("Tree missing ledger \(row.accountName)")
                continue
            }
            XCTAssertEqual(node.balancePaise, row.debitPaise - row.creditPaise,
                           "Mismatch for \(row.accountName)")
        }

        // Spot-check explicit expected values.
        XCTAssertEqual(tree.findLedger(tc.cashId)?.balancePaise, 40000)   // 100 + 500 - 200
        XCTAssertEqual(tree.findLedger(tc.salesId)?.balancePaise, -50000) // credit
        XCTAssertEqual(tree.findLedger(tc.rentId)?.balancePaise, 20000)
        XCTAssertEqual(tree.findLedger(tc.capitalId)?.balancePaise, -10000)
    }

    func testTrialBalanceSeededTotalsMatchExpectedFixture() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let tb = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: tc.fy.endDate)

        XCTAssertEqual(tb.totalDebitPaise, 80000)
        XCTAssertEqual(tb.totalCreditPaise, 80000)

        let rowsById = Dictionary(uniqueKeysWithValues: tb.rows.map { ($0.id, $0) })
        XCTAssertEqual(rowsById[tc.cashId]?.debitPaise, 60000)
        XCTAssertEqual(rowsById[tc.cashId]?.creditPaise, 20000)
        XCTAssertEqual(rowsById[tc.salesId]?.debitPaise, 0)
        XCTAssertEqual(rowsById[tc.salesId]?.creditPaise, 50000)
        XCTAssertEqual(rowsById[tc.rentId]?.debitPaise, 20000)
        XCTAssertEqual(rowsById[tc.rentId]?.creditPaise, 0)
        XCTAssertEqual(rowsById[tc.capitalId]?.debitPaise, 0)
        XCTAssertEqual(rowsById[tc.capitalId]?.creditPaise, 10000)
    }

    func testBooksAreBalancedAcrossAllLedgers() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        await cache.reload()
        guard let tree = cache.tree else {
            return XCTFail("Tree failed to load")
        }
        // Balanced opening + balanced vouchers => sum of all signed leaf balances is zero.
        let sum = tree.allLedgers.reduce(Int64(0)) { $0 + $1.balancePaise }
        XCTAssertEqual(sum, 0)
    }

    func testLiveNetTrialBalanceTotalsTieOutWithSql() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        await cache.reload()
        guard let tree = cache.tree else { return XCTFail("Tree failed to load") }

        // Same net presentation the Dashboard's live trial-balance card uses.
        var dr: Int64 = 0
        var cr: Int64 = 0
        for ledger in tree.allLedgers where ledger.isActive {
            let bal = ledger.balancePaise
            if bal >= 0 { dr += bal } else { cr += -bal }
        }
        XCTAssertEqual(dr, cr) // balanced books

        let tb = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: tc.fy.endDate)
        let sqlNet = tb.rows.reduce(Int64(0)) { $0 + ($1.debitPaise - $1.creditPaise) }
        XCTAssertEqual(dr - cr, sqlNet)
    }

    func testTrialBalanceLiveTotalsMatchAuthoritativeSql() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let tb = try ReportService(db: tc.db, companyId: tc.companyId)
            .trialBalance(asOfDate: tc.fy.endDate)

        let sqlRows = try tc.db.query(
            """
            SELECT a.id,
                   a.opening_balance_paise AS ob,
                   a.opening_balance_side AS obs,
                   COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_accounts a
            LEFT JOIN avelo_ledger_lines l ON l.account_id = a.id
            LEFT JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE a.company_id = ?
              AND a.is_active = 1
              AND (v.id IS NULL OR v.date <= ?)
            GROUP BY a.id, a.opening_balance_paise, a.opening_balance_side
            """,
            bind: [.text(tc.companyId.uuidString), .date(tc.fy.endDate)]
        ) { row in
            (
                try UUIDParsing.required(row.text("id"), field: "sql.trial_balance.account_id"),
                row.int("ob"),
                row.text("obs"),
                row.int("dr"),
                row.int("cr")
            )
        }

        var expectedDebit: Int64 = 0
        var expectedCredit: Int64 = 0
        for (_, openingBalance, openingSide, debitMovement, creditMovement) in sqlRows {
            let signedOpening = openingSide == "debit" ? openingBalance : -openingBalance
            expectedDebit += (signedOpening > 0 ? signedOpening : 0) + debitMovement
            expectedCredit += (signedOpening < 0 ? -signedOpening : 0) + creditMovement
        }

        XCTAssertEqual(tb.totalDebitPaise, expectedDebit)
        XCTAssertEqual(tb.totalCreditPaise, expectedCredit)
    }

    func testGroupBalanceEqualsSumOfChildren() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        await cache.reload()
        guard let tree = cache.tree else {
            return XCTFail("Tree failed to load")
        }
        for root in tree.roots {
            let childSum = root.childGroups.map { $0.balancePaise }.reduce(0, +)
                + root.childLedgers.map { $0.balancePaise }.reduce(0, +)
            XCTAssertEqual(root.balancePaise, childSum, "Group \(root.name) balance != children")
        }
    }

    func testReloadRunsOnBackgroundWorkerAndPublishesTree() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        let backgroundExpectation = expectation(description: "background load")
        cache.onBackgroundLoad = { isMainThread in
            XCTAssertFalse(isMainThread, "AccountTreeCache.reload() should run its heavy load off the main thread")
            backgroundExpectation.fulfill()
        }

        await cache.reload()
        await fulfillment(of: [backgroundExpectation], timeout: 5)

        XCTAssertNotNil(cache.tree)
        XCTAssertEqual(cache.tree?.findLedger(tc.cashId)?.balancePaise, 40000)
    }
}
