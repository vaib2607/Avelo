import XCTest
@testable import Avelo

final class ProfitLossReconciliationTests: XCTestCase {

    private struct SeededProfitLossCompany {
        let db: SQLiteDatabase
        let companyId: Company.ID
        let fy: FinancialYear
        let cashId: Account.ID
        let salesId: Account.ID
        let rentId: Account.ID
    }

    private func makeSeededCompany() throws -> SeededProfitLossCompany {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyId = UUID()
        try AuditTestKeySupport.ensureKey(for: companyId)
        let now = DateFormatters.formatIsoTimestamp(Date())
        try db.execute(
            "INSERT INTO avelo_companies (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [.text(companyId.uuidString), .text("P&L Co"), .text(now), .text(now)]
        )

        let fyId = UUID()
        let start = DateFormatters.parseDate("2024-04-01")!
        let end = DateFormatters.parseDate("2025-03-31")!
        try db.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(fyId.uuidString), .text(companyId.uuidString), .text("2024-25"),
                .date(start), .date(end), .date(start), .text(now)
            ]
        )
        let fy = FinancialYear(
            id: fyId,
            companyId: companyId,
            label: "2024-25",
            startDate: start,
            endDate: end,
            booksBeginDate: start
        )

        try SeedLoader().loadDefaults(into: db, companyId: companyId, financialYearId: fy.id)

        let accounts = AccountRepository(db: db)
        let cashId = try XCTUnwrap(accounts.findByCode("CASH_IN_HAND", companyId: companyId)?.id)
        let salesId = try XCTUnwrap(accounts.findByCode("SALES", companyId: companyId)?.id)
        let rentId = try XCTUnwrap(accounts.findByCode("RENT_EXPENSE", companyId: companyId)?.id)

        return SeededProfitLossCompany(
            db: db,
            companyId: companyId,
            fy: fy,
            cashId: cashId,
            salesId: salesId,
            rentId: rentId
        )
    }

    private func seedActivity(_ tc: SeededProfitLossCompany) throws {
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-06-01")!,
            narration: "Sales receipt",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 50000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
            ]
        ), in: tc.fy)

        _ = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-07-01")!,
            narration: "Rent payment",
            lines: [
                .init(accountId: tc.rentId, amountPaise: 20000, side: .debit),
                .init(accountId: tc.cashId, amountPaise: 20000, side: .credit)
            ]
        ), in: tc.fy)
    }

    func testProfitLossSeededTotalsMatchExpectedFixture() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = try ReportService(db: tc.db, companyId: tc.companyId)
            .profitAndLoss(fromDate: tc.fy.startDate, toDate: tc.fy.endDate, financialYearId: tc.fy.id)

        XCTAssertEqual(report.directIncome.totalPaise, 50000)
        XCTAssertEqual(report.indirectIncome.totalPaise, 0)
        XCTAssertEqual(report.directExpense.totalPaise, 0)
        XCTAssertEqual(report.indirectExpense.totalPaise, 20000)
        XCTAssertEqual(report.totalIncomePaise, 50000)
        XCTAssertEqual(report.totalExpensePaise, 20000)
        XCTAssertEqual(report.netProfitPaise, 30000)
    }

    func testProfitLossLiveTotalsMatchAuthoritativeSql() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = try ReportService(db: tc.db, companyId: tc.companyId)
            .profitAndLoss(fromDate: tc.fy.startDate, toDate: tc.fy.endDate, financialYearId: tc.fy.id)

        let rows = try tc.db.query(
            """
            SELECT a.id,
                   a.opening_balance_paise AS ob,
                   a.opening_balance_side AS obs,
                   g.nature AS nature,
                   g.code AS group_code,
                   COALESCE(SUM(CASE WHEN l.side='debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN l.side='credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_accounts a
            JOIN avelo_account_groups g ON g.id = a.group_id
            LEFT JOIN avelo_ledger_lines l ON l.account_id = a.id
            LEFT JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE a.company_id = ?
              AND a.is_active = 1
              AND (v.id IS NULL OR v.date BETWEEN ? AND ?)
            GROUP BY a.id, a.opening_balance_paise, a.opening_balance_side, g.nature, g.code
            """,
            bind: [.text(tc.companyId.uuidString), .date(tc.fy.startDate), .date(tc.fy.endDate)]
        ) { row in
            (
                row.text("nature"),
                row.text("group_code"),
                row.int("ob"),
                row.text("obs"),
                row.int("dr"),
                row.int("cr")
            )
        }

        var expectedDirectIncome: Int64 = 0
        var expectedIndirectIncome: Int64 = 0
        var expectedDirectExpense: Int64 = 0
        var expectedIndirectExpense: Int64 = 0

        for (nature, groupCode, openingBalance, openingSide, debitMovement, creditMovement) in rows {
            let signedOpening = openingSide == "debit" ? openingBalance : -openingBalance
            switch nature {
            case "income":
                let amount = creditMovement - debitMovement
                    - (signedOpening < 0 ? -signedOpening : 0)
                    + (signedOpening > 0 ? signedOpening : 0)
                // Sales/Purchase Accounts are separate Tally primary groups
                // that roll into direct income/expense, same as the app.
                if groupCode == "DIRECT_INCOME" || groupCode == "SALES_ACCOUNTS" {
                    expectedDirectIncome += amount
                } else if groupCode == "INDIRECT_INCOME" {
                    expectedIndirectIncome += amount
                }
            case "expense":
                let amount = debitMovement - creditMovement
                    + (signedOpening > 0 ? signedOpening : 0)
                    - (signedOpening < 0 ? -signedOpening : 0)
                if groupCode == "DIRECT_EXPENSE" || groupCode == "PURCHASE_ACCOUNTS" {
                    expectedDirectExpense += amount
                } else if groupCode == "INDIRECT_EXPENSE" {
                    expectedIndirectExpense += amount
                }
            default:
                break
            }
        }

        XCTAssertEqual(report.directIncome.totalPaise, expectedDirectIncome)
        XCTAssertEqual(report.indirectIncome.totalPaise, expectedIndirectIncome)
        XCTAssertEqual(report.directExpense.totalPaise, expectedDirectExpense)
        XCTAssertEqual(report.indirectExpense.totalPaise, expectedIndirectExpense)
        XCTAssertEqual(report.totalIncomePaise, expectedDirectIncome + expectedIndirectIncome)
        XCTAssertEqual(report.totalExpensePaise, expectedDirectExpense + expectedIndirectExpense)
    }
}
