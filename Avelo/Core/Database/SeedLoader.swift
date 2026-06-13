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

        enum CodingKeys: String, CodingKey {
            case code, name, nature
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
        let groups: [DefaultChartOfAccountsPayload.Group] = [
            .init(code: "CAPITAL",        name: "Capital Account",      nature: "liabilities", sortOrder: 1),
            .init(code: "LOANS",          name: "Loans (Liability)",    nature: "liabilities", sortOrder: 2),
            .init(code: "CURRENT_LIAB",   name: "Current Liabilities",  nature: "liabilities", sortOrder: 3),
            .init(code: "DUTIES_TAXES",   name: "Duties & Taxes",       nature: "liabilities", sortOrder: 4),
            .init(code: "FIXED_ASSETS",   name: "Fixed Assets",         nature: "assets",      sortOrder: 5),
            .init(code: "INVESTMENTS",    name: "Investments",          nature: "assets",      sortOrder: 6),
            .init(code: "CURRENT_ASSETS", name: "Current Assets",       nature: "assets",      sortOrder: 7),
            .init(code: "STOCK_IN_HAND",  name: "Stock-in-Hand",        nature: "assets",      sortOrder: 8),
            .init(code: "BANK_ACCOUNTS",  name: "Bank Accounts",        nature: "assets",      sortOrder: 9),
            .init(code: "DIRECT_INCOME",  name: "Direct Income",        nature: "income",      sortOrder: 10),
            .init(code: "INDIRECT_INCOME",name: "Indirect Income",      nature: "income",      sortOrder: 11),
            .init(code: "DIRECT_EXPENSE", name: "Direct Expenses",      nature: "expense",     sortOrder: 12),
            .init(code: "INDIRECT_EXPENSE",name: "Indirect Expenses",   nature: "expense",     sortOrder: 13)
        ]

        let ledgers: [DefaultChartOfAccountsPayload.Ledger] = [
            .init(code: "OWNERS_CAPITAL",   name: "Owner's Capital",      under: "CAPITAL",        openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "PARTNERS_CAPITAL", name: "Partner's Capital",    under: "CAPITAL",        openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SECURED_LOAN",     name: "Secured Loan",         under: "LOANS",          openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "UNSECURED_LOAN",   name: "Unsecured Loan",       under: "LOANS",          openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SUNDRY_CREDITORS", name: "Sundry Creditors",     under: "CURRENT_LIAB",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SALARY_PAYABLE",   name: "Salary Payable",       under: "CURRENT_LIAB",   openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
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
            .init(code: "CASH_IN_HAND",     name: "Cash-in-Hand",         under: "CURRENT_ASSETS", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "SUNDRY_DEBTORS",   name: "Sundry Debtors",       under: "CURRENT_ASSETS", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "RAW_MATERIAL",     name: "Raw Material",         under: "STOCK_IN_HAND",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "FINISHED_GOODS",   name: "Finished Goods",       under: "STOCK_IN_HAND",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "BANK_HDFC",        name: "HDFC Bank",            under: "BANK_ACCOUNTS",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: true),
            .init(code: "BANK_SBI",         name: "SBI Bank",             under: "BANK_ACCOUNTS",  openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: true),
            .init(code: "SALES",            name: "Sales",                under: "DIRECT_INCOME",  openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "SERVICE_INCOME",   name: "Service Income",       under: "DIRECT_INCOME",  openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "DISCOUNT_RECEIVED",name: "Discount Received",    under: "INDIRECT_INCOME",openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "INTEREST_RECEIVED",name: "Interest Received",    under: "INDIRECT_INCOME",openingBalancePaise: 0, openingBalanceSide: "credit", isBankAccount: false),
            .init(code: "PURCHASE",         name: "Purchase",             under: "DIRECT_EXPENSE", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
            .init(code: "DIRECT_EXPENSES",  name: "Direct Expenses",      under: "DIRECT_EXPENSE", openingBalancePaise: 0, openingBalanceSide: "debit",  isBankAccount: false),
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
