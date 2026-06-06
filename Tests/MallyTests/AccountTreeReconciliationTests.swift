import XCTest
@testable import Mally

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

    func testTreeBalancesMatchSqlTrialBalance() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        guard let tree = cache.ensureLoaded() else {
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

    func testBooksAreBalancedAcrossAllLedgers() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        guard let tree = cache.ensureLoaded() else {
            return XCTFail("Tree failed to load")
        }
        // Balanced opening + balanced vouchers => sum of all signed leaf balances is zero.
        let sum = tree.allLedgers.reduce(Int64(0)) { $0 + $1.balancePaise }
        XCTAssertEqual(sum, 0)
    }

    func testLiveNetTrialBalanceTotalsTieOutWithSql() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        guard let tree = cache.ensureLoaded() else { return XCTFail("Tree failed to load") }

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

    func testGroupBalanceEqualsSumOfChildren() throws {
        let tc = try TestCompany.make()
        try seedActivity(tc)

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db)
        guard let tree = cache.ensureLoaded() else {
            return XCTFail("Tree failed to load")
        }
        for root in tree.roots {
            let childSum = root.childGroups.map { $0.balancePaise }.reduce(0, +)
                + root.childLedgers.map { $0.balancePaise }.reduce(0, +)
            XCTAssertEqual(root.balancePaise, childSum, "Group \(root.name) balance != children")
        }
    }
}
