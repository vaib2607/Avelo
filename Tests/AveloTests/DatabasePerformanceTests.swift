import XCTest
@testable import Avelo

final class DatabasePerformanceTests: XCTestCase {

    func testPragmaCacheSizeMatchesConfiguredValue() throws {
        let tc = try TestCompany.make()
        defer { tc.db.close() }

        let cacheSize = try tc.db.queryOne("PRAGMA cache_size") { $0.int(0) }
        XCTAssertEqual(cacheSize, -64_000)
    }

    func testLedgerQueryPlanUsesCompositeLedgerIndex() throws {
        let tc = try TestCompany.make()
        defer { tc.db.close() }

        let planRows = try tc.db.query(
            """
            EXPLAIN QUERY PLAN
            SELECT l.account_id, COUNT(*)
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE l.company_id = ? AND l.account_id = ? AND v.date <= ?
            GROUP BY l.account_id
            """,
            bind: [
                .text(tc.companyId.uuidString),
                .text(tc.cashId.uuidString),
                .date(tc.fy.endDate)
            ]
        ) { row in
            row.text(3)
        }

        let details = planRows.joined(separator: "\n")
        XCTAssertTrue(
            details.contains("idx_avelo_lines_company_account_voucher") || details.contains("idx_avelo_lines_account"),
            "Expected planner to use a ledger-line index, got: \(details)"
        )
    }
}
