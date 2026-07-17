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

<<<<<<< HEAD
    func testTreeBalancesMatchSqlTrialBalance() async throws {
=======
    func testTreeBalancesMatchSqlTrialBalance() throws {
>>>>>>> origin/main
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
<<<<<<< HEAD
        await cache.reload()
        guard let tree = cache.tree else {
=======
        guard let tree = cache.ensureLoaded() else {
>>>>>>> origin/main
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

<<<<<<< HEAD
        XCTAssertEqual(tb.totalDebitPaise, 60000)
        XCTAssertEqual(tb.totalCreditPaise, 60000)

        let rowsById = Dictionary(uniqueKeysWithValues: tb.rows.map { ($0.id, $0) })
        XCTAssertEqual(rowsById[tc.cashId]?.debitPaise, 40000)
        XCTAssertEqual(rowsById[tc.cashId]?.creditPaise, 0)
=======
        XCTAssertEqual(tb.totalDebitPaise, 80000)
        XCTAssertEqual(tb.totalCreditPaise, 80000)

        let rowsById = Dictionary(uniqueKeysWithValues: tb.rows.map { ($0.id, $0) })
        XCTAssertEqual(rowsById[tc.cashId]?.debitPaise, 60000)
        XCTAssertEqual(rowsById[tc.cashId]?.creditPaise, 20000)
>>>>>>> origin/main
        XCTAssertEqual(rowsById[tc.salesId]?.debitPaise, 0)
        XCTAssertEqual(rowsById[tc.salesId]?.creditPaise, 50000)
        XCTAssertEqual(rowsById[tc.rentId]?.debitPaise, 20000)
        XCTAssertEqual(rowsById[tc.rentId]?.creditPaise, 0)
        XCTAssertEqual(rowsById[tc.capitalId]?.debitPaise, 0)
        XCTAssertEqual(rowsById[tc.capitalId]?.creditPaise, 10000)
    }

<<<<<<< HEAD
    func testTreeCarriesForwardBalancesIntoLaterFinancialYear() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let secondFYStart = DateFormatters.parseDate("2025-04-01")!
        let secondFYEnd = DateFormatters.parseDate("2026-03-31")!
        let secondFYId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())
        try tc.db.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(secondFYId.uuidString),
                .text(tc.companyId.uuidString),
                .text("2025-26"),
                .date(secondFYStart),
                .date(secondFYEnd),
                .date(secondFYStart),
                .text(now)
            ]
        )

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db, financialYearId: secondFYId)
        await cache.reload()
        XCTAssertEqual(cache.tree?.findLedger(tc.cashId)?.balancePaise, 40000)
        XCTAssertEqual(cache.tree?.findLedger(tc.salesId)?.balancePaise, -50000)
    }

    func testBooksAreBalancedAcrossAllLedgers() async throws {
=======
    func testBooksAreBalancedAcrossAllLedgers() throws {
>>>>>>> origin/main
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
<<<<<<< HEAD
        await cache.reload()
        guard let tree = cache.tree else {
=======
        guard let tree = cache.ensureLoaded() else {
>>>>>>> origin/main
            return XCTFail("Tree failed to load")
        }
        // Balanced opening + balanced vouchers => sum of all signed leaf balances is zero.
        let sum = tree.allLedgers.reduce(Int64(0)) { $0 + $1.balancePaise }
        XCTAssertEqual(sum, 0)
    }

<<<<<<< HEAD
    func testLiveNetTrialBalanceTotalsTieOutWithSql() async throws {
=======
    func testLiveNetTrialBalanceTotalsTieOutWithSql() throws {
>>>>>>> origin/main
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
<<<<<<< HEAD
        await cache.reload()
        guard let tree = cache.tree else { return XCTFail("Tree failed to load") }
=======
        guard let tree = cache.ensureLoaded() else { return XCTFail("Tree failed to load") }
>>>>>>> origin/main

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
<<<<<<< HEAD
            let openingDebit = signedOpening > 0 ? signedOpening : 0
            let openingCredit = signedOpening < 0 ? -signedOpening : 0
            let grossDebit = openingDebit + debitMovement
            let grossCredit = openingCredit + creditMovement
            let net = grossDebit - grossCredit
            expectedDebit += max(net, 0)
            expectedCredit += max(-net, 0)
=======
            expectedDebit += (signedOpening > 0 ? signedOpening : 0) + debitMovement
            expectedCredit += (signedOpening < 0 ? -signedOpening : 0) + creditMovement
>>>>>>> origin/main
        }

        XCTAssertEqual(tb.totalDebitPaise, expectedDebit)
        XCTAssertEqual(tb.totalCreditPaise, expectedCredit)
    }

<<<<<<< HEAD
    func testGroupBalanceEqualsSumOfChildren() async throws {
=======
    func testGroupBalanceEqualsSumOfChildren() throws {
>>>>>>> origin/main
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
<<<<<<< HEAD
        await cache.reload()
        guard let tree = cache.tree else {
=======
        guard let tree = cache.ensureLoaded() else {
>>>>>>> origin/main
            return XCTFail("Tree failed to load")
        }
        for root in tree.roots {
            let childSum = root.childGroups.map { $0.balancePaise }.reduce(0, +)
                + root.childLedgers.map { $0.balancePaise }.reduce(0, +)
            XCTAssertEqual(root.balancePaise, childSum, "Group \(root.name) balance != children")
        }
    }
<<<<<<< HEAD

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

    func testReloadFailsClosedOnLedgerBalanceOverflow() async throws {
        let tc = try TestCompany.make()
        try tc.db.execute(
            "UPDATE avelo_accounts SET opening_balance_paise = ?, opening_balance_side = 'debit' WHERE id = ?",
            [.integer(Int64.max), .text(tc.cashId.uuidString)]
        )
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 1, .debit),
            tc.line(tc.salesId, 1, .credit)
        ]), in: tc.fy)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        await cache.reload()

        XCTAssertNil(cache.tree)
        guard case AppError.businessRule(let message)? = cache.lastError else {
            return XCTFail("Expected overflow businessRule, got \(String(describing: cache.lastError))")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
    }

    func testEnsureLoadedDoesNotSpawnConcurrentReloads() async throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        let started = expectation(description: "reload started")
        let secondStart = expectation(description: "second reload started")
        secondStart.isInverted = true
        let startCounter = LockedCounter()
        cache.onBackgroundLoad = { _ in
            let current = startCounter.increment()
            if current == 1 {
                started.fulfill()
            } else {
                secondStart.fulfill()
            }
            Thread.sleep(forTimeInterval: 0.15)
        }

        _ = cache.ensureLoaded()
        await fulfillment(of: [started], timeout: 5)
        _ = cache.ensureLoaded()
        try await Task.sleep(nanoseconds: 300_000_000)

        await fulfillment(of: [secondStart], timeout: 0.2)
        XCTAssertNil(cache.lastError)
        XCTAssertFalse(cache.isLoading)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
=======
>>>>>>> origin/main
}
