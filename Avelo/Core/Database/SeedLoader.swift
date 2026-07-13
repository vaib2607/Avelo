import Foundation
import os

private let AveloSeedLogger = Logger(subsystem: "com.avelo.desktop", category: "seed")

public struct SeedLoader: Sendable {

    public init() {}

    public func loadDefaults(into db: SQLiteDatabase,
                              companyId: Company.ID,
                              financialYearId: FinancialYear.ID,
                              bundle: Bundle = .main,
                              resourceName: String = "DefaultChartOfAccounts",
                              resourceExtension: String = "json") throws {

        let payload: DefaultChartOfAccountsPayload
        if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
           let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            payload = try dec.decode(DefaultChartOfAccountsPayload.self, from: data)
        } else {
            AveloSeedLogger.info("seed resource missing, using built-in defaults")
            payload = DefaultChartOfDefaults.builtIn
        }

        try db.write { tx in
            for vt in payload.voucherTypes {
                try tx.execute(
                    "INSERT INTO avelo_voucher_types (id, company_id, code, name, abbreviation, is_system, affects_inventory, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        .text(UUID().uuidString),
                        .text(companyId.uuidString),
                        .text(vt.code),
                        .text(vt.name),
                        .text(vt.abbreviation),
                        .bool(vt.isSystem),
                        .bool(vt.affectsInventory),
                        .integer(Int64(vt.sortOrder)),
                        .timestamp(Date())
                    ]
                )
            }

            for g in payload.groups {
                try tx.execute(
                    "INSERT INTO avelo_account_groups (id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at) VALUES (?, ?, NULL, ?, ?, ?, 1, ?, ?)",
                    [
                        .text(UUID().uuidString),
                        .text(companyId.uuidString),
                        .text(g.code),
                        .text(g.name),
                        .text(g.nature),
                        .integer(Int64(g.sortOrder)),
                        .timestamp(Date())
                    ]
                )
            }

            let groups = try tx.query("SELECT id, code FROM avelo_account_groups WHERE company_id = ?",
                                       bind: [.text(companyId.uuidString)]) { r in
                (r.text("id"), r.text("code"))
            }
            var groupByCode: [String: String] = [:]
            for (id, code) in groups { groupByCode[code] = id }

            // Second pass: wire the Tally group hierarchy (all rows inserted
            // with NULL parent above, so ordering never matters).
            for g in payload.groups {
                guard let under = g.under else { continue }
                guard let parentId = groupByCode[under] else {
                    throw AppError.businessRule("Seed loader: unknown parent group code '\(under)' for group '\(g.code)'")
                }
                try tx.execute(
                    "UPDATE avelo_account_groups SET parent_group_id = ? WHERE company_id = ? AND code = ?",
                    [.text(parentId), .text(companyId.uuidString), .text(g.code)]
                )
            }

            for l in payload.ledgers {
                guard let gid = groupByCode[l.under] else {
                    throw AppError.businessRule("Seed loader: unknown group code '\(l.under)' for ledger '\(l.code)'")
                }
                try tx.execute(
                    "INSERT INTO avelo_accounts (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side, is_active, is_bank_account, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)",
                    [
                        .text(UUID().uuidString),
                        .text(companyId.uuidString),
                        .text(gid),
                        .text(l.code),
                        .text(l.name),
                        .integer(l.openingBalancePaise),
                        .text(l.openingBalanceSide),
                        .bool(l.isBankAccount),
                        .timestamp(Date()),
                        .timestamp(Date())
                    ]
                )
            }

            for vt in VoucherType.Code.allCases {
                try tx.execute(
                    "INSERT OR REPLACE INTO avelo_voucher_sequences (company_id, financial_year_id, voucher_type_code, last_number, prefix, suffix, padding) VALUES (?, ?, ?, 0, ?, NULL, ?)",
                    [
                        .text(companyId.uuidString),
                        .text(financialYearId.uuidString),
                        .text(vt.rawValue),
                        .text(vt.defaultPrefix),
                        .integer(Int64(vt.defaultPadding))
                    ]
                )
            }
        }
    }
}

struct DefaultChartOfAccountsPayload: Codable, Sendable {
    let groups: [Group]
    let ledgers: [Ledger]
    let voucherTypes: [VoucherTypeSeed]

    struct Group: Codable, Sendable {
        let code: String
        let name: String
        let nature: String
        let sortOrder: Int
        var under: String? = nil

        enum CodingKeys: String, CodingKey {
            case code, name, nature, under
            case sortOrder = "sort_order"
        }
    }

    struct Ledger: Codable, Sendable {
        let code: String
        let name: String
        let under: String
        let openingBalancePaise: Int64
        let openingBalanceSide: String
        let isBankAccount: Bool

        enum CodingKeys: String, CodingKey {
            case code, name, under
            case openingBalancePaise = "opening_balance_paise"
            case openingBalanceSide = "opening_balance_side"
            case isBankAccount = "is_bank_account"
        }
    }

    struct VoucherTypeSeed: Codable, Sendable {
        let code: String
        let name: String
        let abbreviation: String
        let isSystem: Bool
        let affectsInventory: Bool
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case code, name, abbreviation
            case isSystem = "is_system"
            case affectsInventory = "affects_inventory"
            case sortOrder = "sort_order"
        }
    }
}

enum DefaultChartOfDefaults {

    static let builtIn: DefaultChartOfAccountsPayload = {
        // Tally's 28 reserved groups: 15 primary + 13 sub-groups.
        let groups: [DefaultChartOfAccountsPayload.Group] = [
            // Primary — capital nature
            .init(code: "CAPITAL",        name: "Capital Account",      nature: "liabilities", sortOrder: 1),
            .init(code: "LOANS",          name: "Loans (Liability)",    nature: "liabilities", sortOrder: 2),
            .init(code: "CURRENT_LIAB",   name: "Current Liabilities",  nature: "liabilities", sortOrder: 3),
            .init(code: "FIXED_ASSETS",   name: "Fixed Assets",         nature: "assets",      sortOrder: 4),
            .init(code: "INVESTMENTS",    name: "Investments",          nature: "assets",      sortOrder: 5),
            .init(code: "CURRENT_ASSETS", name: "Current Assets",       nature: "assets",      sortOrder: 6),
            .init(code: "MISC_EXPENSES_ASSET", name: "Misc. Expenses (Asset)", nature: "assets", sortOrder: 7),
            .init(code: "SUSPENSE",       name: "Suspense A/c",         nature: "liabilities", sortOrder: 8),
            .init(code: "BRANCH_DIVISIONS", name: "Branch / Divisions", nature: "liabilities", sortOrder: 9),
            // Primary — revenue nature
            .init(code: "SALES_ACCOUNTS", name: "Sales Accounts",       nature: "income",      sortOrder: 10),
            .init(code: "PURCHASE_ACCOUNTS", name: "Purchase Accounts", nature: "expense",     sortOrder: 11),
            .init(code: "DIRECT_INCOME",  name: "Direct Income",        nature: "income",      sortOrder: 12),
            .init(code: "INDIRECT_INCOME",name: "Indirect Income",      nature: "income",      sortOrder: 13),
            .init(code: "DIRECT_EXPENSE", name: "Direct Expenses",      nature: "expense",     sortOrder: 14),
            .init(code: "INDIRECT_EXPENSE",name: "Indirect Expenses",   nature: "expense",     sortOrder: 15),
            // Sub-groups
            // Note: kept as a primary (not nested under CAPITAL) because
            // Avelo enforces leaf-only posting and Owner's/Partner's Capital
            // are seeded directly on CAPITAL; a user can re-parent this via
            // the Groups master if they want the Tally-exact nesting.
            .init(code: "RESERVES_SURPLUS", name: "Reserves & Surplus", nature: "liabilities", sortOrder: 16),
            .init(code: "BANK_OD",        name: "Bank OD A/c",          nature: "liabilities", sortOrder: 17, under: "LOANS"),
            .init(code: "SECURED_LOANS",  name: "Secured Loans",        nature: "liabilities", sortOrder: 18, under: "LOANS"),
            .init(code: "UNSECURED_LOANS", name: "Unsecured Loans",     nature: "liabilities", sortOrder: 19, under: "LOANS"),
            .init(code: "DUTIES_TAXES",   name: "Duties & Taxes",       nature: "liabilities", sortOrder: 20, under: "CURRENT_LIAB"),
            .init(code: "PROVISIONS",     name: "Provisions",           nature: "liabilities", sortOrder: 21, under: "CURRENT_LIAB"),
            .init(code: "SUNDRY_CREDITORS", name: "Sundry Creditors",   nature: "liabilities", sortOrder: 22, under: "CURRENT_LIAB"),
            .init(code: "BANK_ACCOUNTS",  name: "Bank Accounts",        nature: "assets",      sortOrder: 23, under: "CURRENT_ASSETS"),
            .init(code: "CASH_IN_HAND",   name: "Cash-in-Hand",         nature: "assets",      sortOrder: 24, under: "CURRENT_ASSETS"),
            .init(code: "DEPOSITS_ASSET", name: "Deposits (Asset)",     nature: "assets",      sortOrder: 25, under: "CURRENT_ASSETS"),
            .init(code: "LOANS_ADVANCES_ASSET", name: "Loans & Advances (Asset)", nature: "assets", sortOrder: 26, under: "CURRENT_ASSETS"),
            .init(code: "STOCK_IN_HAND",  name: "Stock-in-Hand",        nature: "assets",      sortOrder: 27, under: "CURRENT_ASSETS"),
            .init(code: "SUNDRY_DEBTORS", name: "Sundry Debtors",       nature: "assets",      sortOrder: 28, under: "CURRENT_ASSETS")
        ]

        let ledgers: [DefaultChartOfAccountsPayload.Ledger] = [
            .init(code: "OWNERS_CAPITAL",   name: "Owner's Capital",      under: "CAPITAL",        openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "PARTNERS_CAPITAL", name: "Partner's Capital",    under: "CAPITAL",        openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SECURED_LOAN",     name: "Secured Loan",         under: "SECURED_LOANS",  openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "UNSECURED_LOAN",   name: "Unsecured Loan",       under: "UNSECURED_LOANS", openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SUNDRY_CREDITORS", name: "Sundry Creditors",     under: "SUNDRY_CREDITORS", openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SALARY_PAYABLE",   name: "Salary Payable",       under: "SUNDRY_CREDITORS", openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "CGST_INPUT",       name: "CGST Input",           under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "CGST_OUTPUT",      name: "CGST Output",          under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SGST_INPUT",       name: "SGST Input",           under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "SGST_OUTPUT",      name: "SGST Output",          under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "IGST_INPUT",       name: "IGST Input",           under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "IGST_OUTPUT",      name: "IGST Output",          under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "CESS",             name: "CESS",                 under: "DUTIES_TAXES",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "FURNITURE",        name: "Furniture",            under: "FIXED_ASSETS",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "PLANT_MACHINERY",  name: "Plant & Machinery",    under: "FIXED_ASSETS",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "BUILDING",         name: "Building",             under: "FIXED_ASSETS",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "COMPUTER",         name: "Computer",             under: "FIXED_ASSETS",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "VEHICLE",          name: "Vehicle",              under: "FIXED_ASSETS",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "CASH_IN_HAND",     name: "Cash-in-Hand",         under: "CASH_IN_HAND",   openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "SUNDRY_DEBTORS",   name: "Sundry Debtors",       under: "SUNDRY_DEBTORS", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "RAW_MATERIAL",     name: "Raw Material",         under: "STOCK_IN_HAND",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "FINISHED_GOODS",   name: "Finished Goods",       under: "STOCK_IN_HAND",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "BANK_HDFC",        name: "HDFC Bank",            under: "BANK_ACCOUNTS",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: true),
            .init(code: "BANK_SBI",         name: "SBI Bank",             under: "BANK_ACCOUNTS",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: true),
            .init(code: "SALES",            name: "Sales",                under: "SALES_ACCOUNTS", openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SERVICE_INCOME",   name: "Service Income",       under: "DIRECT_INCOME",  openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "DISCOUNT_RECEIVED",name: "Discount Received",    under: "INDIRECT_INCOME",openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "INTEREST_RECEIVED",name: "Interest Received",    under: "INDIRECT_INCOME",openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "PURCHASE",         name: "Purchase",             under: "PURCHASE_ACCOUNTS", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "DIRECT_EXPENSES",  name: "Direct Expenses",      under: "DIRECT_EXPENSE", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "ROUND_OFF",        name: "Round Off",            under: "INDIRECT_EXPENSE",openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "SALARY_EXPENSE",   name: "Salary Expense",       under: "INDIRECT_EXPENSE",openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "RENT_EXPENSE",     name: "Rent Expense",         under: "INDIRECT_EXPENSE",openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "ELECTRICITY_EXPENSE",name:"Electricity Expense",  under: "INDIRECT_EXPENSE",openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "OFFICE_EXPENSE",   name: "Office Expense",       under: "INDIRECT_EXPENSE",openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false)
        ]

        let voucherTypes: [DefaultChartOfAccountsPayload.VoucherTypeSeed] = VoucherType.Code.allCases.enumerated().map { (i, c) in
            .init(code: c.rawValue,
                  name: c.displayName,
                  abbreviation: c.abbreviation,
                  isSystem: true,
                  affectsInventory: c.affectsInventory,
                  sortOrder: i)
        }

        return DefaultChartOfAccountsPayload(groups: groups, ledgers: ledgers, voucherTypes: voucherTypes)
    }()
}
