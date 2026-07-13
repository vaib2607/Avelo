import Foundation

public enum DemoCompanySeeder {
    public static let companyName = "Demo Company"
    public static let companyDisplayName = "Demo Co"

    public static func ensureDemoCompany(manager: DatabaseManager) async throws -> CompanyRegistryEntry {
        let existing = try await manager.listCompanies().first(where: { $0.name == companyDisplayName })
        if let existing {
            try await seedIfNeeded(manager: manager, companyId: existing.id, companyName: existing.name)
            return existing
        }

        let company = try await CompanyService.create(
            companyInput: .init(
                name: companyDisplayName,
                addressLine1: "12 Market Road",
                addressLine2: "Industrial Estate",
                city: "Pune",
                state: "Maharashtra",
                pincode: "411001",
                country: "India",
                gstin: nil,
                pan: nil
            ),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        try await seedIfNeeded(manager: manager, companyId: company.id, companyName: company.name)
        return CompanyRegistryEntry(id: company.id, name: company.name, sqliteFileName: "\(company.id.uuidString).sqlite")
    }

    public static func seedIfNeeded(manager: DatabaseManager, companyId: Company.ID, companyName: String) async throws {
        let handle = try await manager.openCompany(id: companyId)
        let db = handle.db

        let company = try CompanyRepository(db: db).findById(companyId)
        guard company != nil else { return }

        let accountCount = try db.queryOne("SELECT COUNT(*) FROM avelo_accounts WHERE company_id = ?", bind: [.text(companyId.uuidString)]) { $0.int(0) } ?? 0
        let voucherCount = try db.queryOne("SELECT COUNT(*) FROM avelo_vouchers WHERE company_id = ?", bind: [.text(companyId.uuidString)]) { $0.int(0) } ?? 0
        if accountCount >= 12, voucherCount >= 4 { return }

        try populateDemoData(db: db, companyId: companyId, companyName: companyName)
    }

    private static func populateDemoData(db: SQLiteDatabase, companyId: Company.ID, companyName: String) throws {
        let accounts = AccountService(db: db, companyId: companyId)
        let fyService = FinancialYearService(db: db, companyId: companyId)
        let vouchers = VoucherService(db: db, companyId: companyId)
        let inventory = InventoryService(db: db, companyId: companyId)
        let payroll = PayrollService(db: db, companyId: companyId)
        let report = ReportService(db: db, companyId: companyId)

        guard let fy = try fyService.mostRecent() else { return }
        try db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 1, inventory_link_mode = ?, updated_at = ? WHERE id = ?",
            [.text(InventoryLinkMode.autoPrompt.rawValue), .timestamp(Date()), .text(companyId.uuidString)]
        )

        let groups = try accounts.listGroups()
        func group(_ code: String) throws -> AccountGroup {
            guard let g = groups.first(where: { $0.code == code }) else { throw AppError.notFound("Group \(code)") }
            return g
        }

        // Post to Tally's leaf sub-groups, not their non-leaf parents
        // (Avelo enforces leaf-only ledger posting).
        let sundryDebtors = try group("SUNDRY_DEBTORS")
        let sundryCreditors = try group("SUNDRY_CREDITORS")
        let directIncome = try group("DIRECT_INCOME")
        let indirectExpense = try group("INDIRECT_EXPENSE")

        let seedAccounts = try accounts.listActiveAccounts()
        func account(_ code: String) throws -> Account {
            guard let a = seedAccounts.first(where: { $0.code == code }) else { throw AppError.notFound("Account \(code)") }
            return a
        }

        let cash = try account("CASH_IN_HAND")
        let bank = try account("BANK_HDFC")
        _ = try account("SALES")
        let salaryExpense = try account("SALARY_EXPENSE")

        let customer = try accounts.createAccount(.init(code: "CUST_DEMO", name: "\(companyName) Customer", groupId: sundryDebtors.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let vendor = try accounts.createAccount(.init(code: "VEND_DEMO", name: "\(companyName) Vendor", groupId: sundryCreditors.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        let consultingIncome = try accounts.createAccount(.init(code: "CONSULTING", name: "Consulting Income", groupId: directIncome.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        let travelExpense = try accounts.createAccount(.init(code: "TRAVEL_EXP", name: "Travel Expense", groupId: indirectExpense.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let salaryPayable = try accounts.createAccount(.init(code: "SAL_PAY", name: "Salary Payable Demo", groupId: sundryCreditors.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        let officeExpense = try accounts.createAccount(.init(code: "OFFICE_SUP", name: "Office Supplies", groupId: indirectExpense.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))

        let serviceInvoice = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-04-12")!, partyAccountId: customer.id, narration: "Demo consulting invoice", lines: [.init(accountId: customer.id, amountPaise: 125_000, side: .debit), .init(accountId: consultingIncome.id, amountPaise: 125_000, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .receipt, date: DateFormatters.parseDate("2024-04-14")!, partyAccountId: customer.id, narration: "Customer receipt", lines: [.init(accountId: cash.id, amountPaise: 125_000, side: .debit), .init(accountId: customer.id, amountPaise: 125_000, side: .credit)]), in: fy)
        let paymentVoucher = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .payment, date: DateFormatters.parseDate("2024-05-06")!, partyAccountId: vendor.id, narration: "Vendor payment by bank", lines: [.init(accountId: vendor.id, amountPaise: 58_000, side: .debit), .init(accountId: bank.id, amountPaise: 58_000, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-05-10")!, narration: "Salary provision", lines: [.init(accountId: salaryExpense.id, amountPaise: 42_500, side: .debit), .init(accountId: salaryPayable.id, amountPaise: 42_500, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-05-12")!, narration: "Travel reimbursement", lines: [.init(accountId: travelExpense.id, amountPaise: 9_500, side: .debit), .init(accountId: cash.id, amountPaise: 9_500, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-05-15")!, narration: "Office supplies", lines: [.init(accountId: officeExpense.id, amountPaise: 6_250, side: .debit), .init(accountId: cash.id, amountPaise: 6_250, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .contra, date: DateFormatters.parseDate("2024-05-18")!, narration: "Cash deposit to bank", lines: [.init(accountId: bank.id, amountPaise: 20_000, side: .debit), .init(accountId: cash.id, amountPaise: 20_000, side: .credit)]), in: fy)

        let item = try inventory.createItem(code: "ITEM-001", name: "Demo Widget", unit: "Nos")
        let serviceItem = try inventory.createItem(code: "ITEM-002", name: "Demo Service Pack", unit: "Pack")
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-04-12")!, type: .stockIn, quantity: 20, ratePaise: 1_200, voucherId: serviceInvoice.voucher.id, notes: "Opening demo stock")
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-02")!, type: .stockOut, quantity: 8, ratePaise: 1_300, voucherId: serviceInvoice.voucher.id, notes: "Demo issue")
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-18")!, type: .adjustment, quantity: 5, ratePaise: 1_250, notes: "Cycle count adjustment")
        try inventory.recordMovement(itemId: serviceItem.id, date: DateFormatters.parseDate("2024-05-20")!, type: .stockIn, quantity: 4, ratePaise: 4_500, notes: "Service pack stock-in")
        try inventory.recordMovement(itemId: serviceItem.id, date: DateFormatters.parseDate("2024-05-22")!, type: .stockIn, quantity: 1, ratePaise: 4_500, notes: "Returned demo pack")

        let employeeA = try payroll.createEmployee(name: "Priya Shah", employeeCode: "EMP-001", designation: "Accounts Executive", pan: "ABCDE1234F", baseSalaryPaise: 40_000)
        let employeeB = try payroll.createEmployee(name: "Arjun Mehta", employeeCode: "EMP-002", designation: "Sales Lead", pan: "AAAPM4321Q", baseSalaryPaise: 48_000)
        _ = try payroll.postEntry(employeeId: employeeA.id, monthYear: 202404, deductionsPaise: 1_500, financialYearId: fy.id, salaryExpenseAccountId: salaryExpense.id, paymentAccountId: salaryPayable.id)
        _ = try payroll.postEntry(employeeId: employeeA.id, monthYear: 202405, deductionsPaise: 2_000, financialYearId: fy.id, salaryExpenseAccountId: salaryExpense.id, paymentAccountId: salaryPayable.id)
        _ = try payroll.postEntry(employeeId: employeeB.id, monthYear: 202404, deductionsPaise: 2_500, financialYearId: fy.id, salaryExpenseAccountId: salaryExpense.id, paymentAccountId: salaryPayable.id)

        try BankReconciliationRepository(db: db).upsert(.init(id: UUID(), companyId: companyId, bankAccountId: bank.id, voucherId: serviceInvoice.voucher.id, statementDate: DateFormatters.parseDate("2024-04-14")!, statementAmountPaise: 125_000, isCleared: true, clearedAt: Date(), note: "Auto-matched demo receipt"))
        try BankReconciliationRepository(db: db).upsert(.init(id: UUID(), companyId: companyId, bankAccountId: bank.id, voucherId: paymentVoucher.voucher.id, statementDate: DateFormatters.parseDate("2024-05-06")!, statementAmountPaise: -58_000, isCleared: true, clearedAt: Date(), note: "Demo payment clearing"))

        _ = try report.trialBalance(asOfDate: fy.endDate, financialYearId: fy.id)
        _ = try report.balanceSheet(asOfDate: fy.endDate, financialYearId: fy.id)
        _ = try report.profitAndLoss(fromDate: fy.startDate, toDate: fy.endDate, financialYearId: fy.id)
        _ = try report.dayBook(fromDate: fy.startDate, toDate: fy.endDate)
        _ = try report.ledger(accountId: cash.id, financialYearId: fy.id, fromDate: fy.startDate, toDate: fy.endDate)
    }
}
