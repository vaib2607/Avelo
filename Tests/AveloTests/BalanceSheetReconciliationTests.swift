import XCTest
@testable import Avelo

final class BalanceSheetReconciliationTests: XCTestCase {

    private struct SeededBalanceSheetCompany {
        let db: SQLiteDatabase
        let companyId: Company.ID
        let fy: FinancialYear
        let cashId: Account.ID
        let salesId: Account.ID
        let rentId: Account.ID
    }

    private func makeSeededCompany() throws -> SeededBalanceSheetCompany {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyId = UUID()
<<<<<<< HEAD
        try AuditTestKeySupport.ensureKey(for: companyId)
=======
>>>>>>> origin/main
        let now = DateFormatters.formatIsoTimestamp(Date())
        try db.execute(
            "INSERT INTO avelo_companies (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [.text(companyId.uuidString), .text("Balance Sheet Co"), .text(now), .text(now)]
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

        return SeededBalanceSheetCompany(
            db: db,
            companyId: companyId,
            fy: fy,
            cashId: cashId,
            salesId: salesId,
            rentId: rentId
        )
    }

    private func seedActivity(_ tc: SeededBalanceSheetCompany) throws {
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

    func testBalanceSheetSeededTotalsMatchExpectedFixture() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = try ReportService(db: tc.db, companyId: tc.companyId)
            .balanceSheet(asOfDate: tc.fy.endDate, financialYearId: tc.fy.id)

        XCTAssertEqual(report.totalAssetsPaise, 30000)
        XCTAssertEqual(report.totalLiabilitiesPaise, 0)
        XCTAssertEqual(report.totalEquityPaise, 30000)
        XCTAssertEqual(report.balancingEquityPaise, 30000)

        let assetSections = Dictionary(uniqueKeysWithValues: report.assets.map { ($0.title, $0.totalPaise) })
        let liabilitySections = Dictionary(uniqueKeysWithValues: report.liabilities.map { ($0.title, $0.totalPaise) })

<<<<<<< HEAD
        // Section title is now the ledger's immediate leaf group ("Cash-in-Hand"),
        // not the non-leaf "Current Assets" ancestor, now that the seeded chart
        // mirrors Tally's Current Assets sub-group hierarchy.
        XCTAssertEqual(assetSections["Cash-in-Hand"], 30000)
=======
        XCTAssertEqual(assetSections["Current Assets"], 30000)
>>>>>>> origin/main
        XCTAssertTrue(liabilitySections.isEmpty)
    }

    func testBalanceSheetLiveTotalsMatchAuthoritativeSql() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = try ReportService(db: tc.db, companyId: tc.companyId)
            .balanceSheet(asOfDate: tc.fy.endDate, financialYearId: tc.fy.id)

        let rows = try tc.db.query(
            """
            SELECT a.id,
                   a.opening_balance_paise AS ob,
                   a.opening_balance_side AS obs,
                   g.nature AS nature,
                   g.name AS group_name,
                   COALESCE(SUM(CASE WHEN l.side='debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN l.side='credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_accounts a
            JOIN avelo_account_groups g ON g.id = a.group_id
            LEFT JOIN avelo_ledger_lines l ON l.account_id = a.id
            LEFT JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE a.company_id = ?
              AND a.is_active = 1
              AND (v.id IS NULL OR v.date <= ?)
            GROUP BY a.id, a.opening_balance_paise, a.opening_balance_side, g.nature, g.name
            """,
            bind: [.text(tc.companyId.uuidString), .date(tc.fy.endDate)]
        ) { row in
            (
                row.text("nature"),
                row.text("group_name"),
                row.int("ob"),
                row.text("obs"),
                row.int("dr"),
                row.int("cr")
            )
        }

        var expectedAssets: Int64 = 0
        var expectedLiabilities: Int64 = 0
        var expectedSectionTotals: [String: Int64] = [:]

        for (nature, groupName, openingBalance, openingSide, debitMovement, creditMovement) in rows {
            let signedOpening = openingSide == "debit" ? openingBalance : -openingBalance
            switch nature {
            case "assets":
                let amount = debitMovement - creditMovement + signedOpening
                if amount != 0 {
                    expectedAssets += amount
                    expectedSectionTotals[groupName, default: 0] += amount
                }
            case "liabilities":
                let amount = creditMovement - debitMovement - signedOpening
                if amount != 0 {
                    expectedLiabilities += amount
                    expectedSectionTotals[groupName, default: 0] += amount
                }
            default:
                break
            }
        }

        XCTAssertEqual(report.totalAssetsPaise, expectedAssets)
        XCTAssertEqual(report.totalLiabilitiesPaise, expectedLiabilities)
        XCTAssertEqual(report.totalEquityPaise, expectedAssets - expectedLiabilities)
        XCTAssertEqual(report.balancingEquityPaise, expectedAssets - expectedLiabilities)

        let assetSections = Dictionary(uniqueKeysWithValues: report.assets.map { ($0.title, $0.totalPaise) })
        let liabilitySections = Dictionary(uniqueKeysWithValues: report.liabilities.map { ($0.title, $0.totalPaise) })
        for (groupName, total) in expectedSectionTotals {
            if let assetTotal = assetSections[groupName] {
                XCTAssertEqual(assetTotal, total)
            }
            if let liabilityTotal = liabilitySections[groupName] {
                XCTAssertEqual(liabilityTotal, total)
            }
        }
    }
<<<<<<< HEAD

    func testBalanceSheetIncludesAssetGroupsOutsideTheDefaultCurrentAssetRoots() throws {
        let tc = try makeSeededCompany()
        let group = try XCTUnwrap(
            AccountGroupRepository(db: tc.db).listForCompany(tc.companyId).first { $0.code == "MISC_EXPENSES_ASSET" }
        )
        let account = try AccountService(db: tc.db, companyId: tc.companyId).createAccount(.init(
            code: "DEFERRED_ASSET",
            name: "Deferred Asset",
            groupId: group.id,
            openingBalancePaise: 1_000,
            openingBalanceSide: .debit,
            gstin: nil,
            existingAccountId: nil
        ))

        let report = try ReportService(db: tc.db, companyId: tc.companyId).balanceSheet(
            asOfDate: tc.fy.endDate,
            financialYearId: tc.fy.id
        )

        XCTAssertEqual(report.totalAssetsPaise, 1_000)
        XCTAssertTrue(report.assets.flatMap(\.rows).contains { $0.id == account.id })
    }
=======
>>>>>>> origin/main
}
