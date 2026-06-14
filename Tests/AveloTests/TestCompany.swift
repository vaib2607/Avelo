import Foundation
@testable import Avelo

/// Builds a fully-migrated in-memory company database seeded with a small,
/// balanced chart of accounts for service- and tree-level tests.
struct TestCompany {
    let db: SQLiteDatabase
    let companyId: Company.ID
    let fy: FinancialYear

    // Groups
    let assetsGroupId: AccountGroup.ID
    let incomeGroupId: AccountGroup.ID
    let expenseGroupId: AccountGroup.ID
    let capitalGroupId: AccountGroup.ID

    // Ledgers
    let cashId: Account.ID
    let salesId: Account.ID
    let rentId: Account.ID
    let capitalId: Account.ID

    static func make() throws -> TestCompany {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)
        return try seed(into: db, companyId: UUID(), companyName: "Test Co")
    }

    static func makeOnDisk(name: String = "Test Co") throws -> (fixture: TestCompany, cleanupURL: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("avelo-benchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("company.sqlite")
        let db = try SQLiteDatabase(path: dbURL.path)
        try MigrationRunner().runMigrations(on: db)
        let fixture = try seed(into: db, companyId: UUID(), companyName: name)
        return (fixture, root)
    }

    static func seed(into db: SQLiteDatabase,
                     companyId: Company.ID,
                     companyName: String = "Test Co") throws -> TestCompany {
        let now = DateFormatters.formatIsoTimestamp(Date())
        try db.execute(
            "INSERT INTO avelo_companies (id, name, is_inventory_enabled, inventory_link_mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            [.text(companyId.uuidString), .text(companyName), .bool(true), .text(InventoryLinkMode.autoPrompt.rawValue), .text(now), .text(now)]
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
        let fy = FinancialYear(id: fyId, companyId: companyId, label: "2024-25",
                               startDate: start, endDate: end, booksBeginDate: start)

        func insertGroup(_ code: String, _ name: String, _ nature: String, sort: Int) throws -> UUID {
            let id = UUID()
            try db.execute(
                """
                INSERT INTO avelo_account_groups
                (id, company_id, code, name, nature, sort_order, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(id.uuidString), .text(companyId.uuidString), .text(code),
                    .text(name), .text(nature), .integer(Int64(sort)), .text(now)
                ]
            )
            return id
        }

        func insertAccount(_ code: String, _ name: String, group: UUID,
                           openingPaise: Int64, side: String) throws -> UUID {
            let id = UUID()
            try db.execute(
                """
                INSERT INTO avelo_accounts
                (id, company_id, group_id, code, name, opening_balance_paise,
                 opening_balance_side, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(id.uuidString), .text(companyId.uuidString), .text(group.uuidString),
                    .text(code), .text(name), .integer(openingPaise),
                    .text(side), .text(now), .text(now)
                ]
            )
            return id
        }

        let assets = try insertGroup("1000", "Current Assets", "assets", sort: 0)
        let capital = try insertGroup("3000", "Capital Account", "liabilities", sort: 1)
        let income = try insertGroup("4000", "Sales Accounts", "income", sort: 2)
        let expense = try insertGroup("5000", "Indirect Expenses", "expense", sort: 3)

        let cash = try insertAccount("1001", "Cash", group: assets, openingPaise: 10000, side: "debit")
        let capitalAcc = try insertAccount("3001", "Capital", group: capital, openingPaise: 10000, side: "credit")
        let sales = try insertAccount("4001", "Sales", group: income, openingPaise: 0, side: "credit")
        let rent = try insertAccount("5001", "Rent", group: expense, openingPaise: 0, side: "debit")

        return TestCompany(
            db: db, companyId: companyId, fy: fy,
            assetsGroupId: assets, incomeGroupId: income, expenseGroupId: expense, capitalGroupId: capital,
            cashId: cash, salesId: sales, rentId: rent, capitalId: capitalAcc
        )
    }

    func line(_ accountId: Account.ID, _ amount: Int64, _ side: EntrySide) -> VoucherDraft.Line {
        VoucherDraft.Line(accountId: accountId, amountPaise: amount, side: side)
    }

    func draft(type: VoucherType.Code = .journal,
               on dateString: String,
               narration: String = "Test",
               lines: [VoucherDraft.Line]) -> VoucherDraft {
        VoucherDraft(mode: .create, voucherTypeCode: type,
                     date: DateFormatters.parseDate(dateString)!,
                     narration: narration, lines: lines)
    }
}
