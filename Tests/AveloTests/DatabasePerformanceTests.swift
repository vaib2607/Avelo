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

    func testVoucherListQueryPlanUsesCompanyDateIndex() throws {
        let tc = try TestCompany.make()
        defer { tc.db.close() }

        let planRows = try tc.db.query(
            """
            EXPLAIN QUERY PLAN
            SELECT v.id, v.company_id, v.financial_year_id, v.voucher_type_code, v.number, v.date,
                   v.party_account_id, v.narration, v.is_reversal, v.reversal_of_id,
                   v.is_posted, v.total_paise, v.created_at, v.updated_at, a.name AS party_name
            FROM avelo_vouchers v
            LEFT JOIN avelo_accounts a ON a.id = v.party_account_id
            WHERE v.company_id = ? AND v.date >= ? AND v.date <= ?
            ORDER BY v.date DESC, v.number DESC LIMIT ? OFFSET ?
            """,
            bind: [
                .text(tc.companyId.uuidString),
                .date(tc.fy.startDate),
                .date(tc.fy.endDate),
                .integer(200),
                .integer(0)
            ]
        ) { row in
            row.text(3)
        }

        let details = planRows.joined(separator: "\n")
        XCTAssertTrue(
            details.contains("idx_avelo_vouchers_company_date"),
            "Expected planner to use voucher company/date index, got: \(details)"
        )
    }

    func testDayBookQueryPlanUsesVoucherCompanyDateIndex() throws {
        let tc = try TestCompany.make()
        defer { tc.db.close() }

        let planRows = try tc.db.query(
            """
            EXPLAIN QUERY PLAN
            SELECT v.id, v.created_at, v.number, v.voucher_type_code, v.narration,
                   pa.name AS party_name,
                   COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise ELSE 0 END), 0) AS total_debit,
                   COALESCE(SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END), 0) AS total_credit
            FROM avelo_vouchers v
            LEFT JOIN avelo_accounts pa ON pa.id = v.party_account_id
            LEFT JOIN avelo_ledger_lines l ON l.voucher_id = v.id AND l.company_id = v.company_id
            WHERE v.company_id = ? AND v.date BETWEEN ? AND ?
            GROUP BY v.id, v.created_at, v.number, v.voucher_type_code, v.narration, pa.name
            ORDER BY v.date ASC, v.created_at ASC, v.number ASC
            """,
            bind: [
                .text(tc.companyId.uuidString),
                .date(tc.fy.startDate),
                .date(tc.fy.endDate)
            ]
        ) { row in
            row.text(3)
        }

        let details = planRows.joined(separator: "\n")
        XCTAssertTrue(
            details.contains("idx_avelo_vouchers_company_date"),
            "Expected planner to use voucher company/date index for day book, got: \(details)"
        )
    }
}
