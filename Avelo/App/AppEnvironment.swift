import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
public final class AppEnvironment {

    public var companyContext: CompanyContext?
    public var globalError: AppError?
    public var banner: BannerPayload?
    public var isBusy: Bool = false
    public var accountTree: AccountTreeCache?
    public var dataRevision: Int = 0

    /// Non-nil when the app could not open its normal data location and had to
    /// degrade (e.g. to a temporary directory). Surfaced to the user on launch.
    public var startupError: AppError?

    public let manager: DatabaseManager
    public let router: AppRouter
    public let keyboard: KeyboardRouter
    public let registry: RegistryRepository
    public let backupService: BackupService
    public let shouldAutoOpenDemoCompany: Bool

    @MainActor
    public init() {
        self.router = AppRouter()
        self.keyboard = KeyboardRouter()

        let bootstrap = AppEnvironment.makeStores()
        self.manager = bootstrap.stores.manager
        self.registry = RegistryRepository(db: bootstrap.stores.registryDb)
        self.backupService = BackupService(manager: bootstrap.stores.manager)
        self.shouldAutoOpenDemoCompany = ProcessInfo.processInfo.environment["AVELO_OPEN_DEMO"] == "1"
        self.startupError = bootstrap.error
    }

    @MainActor
    init(manager: DatabaseManager,
         router: AppRouter,
         keyboard: KeyboardRouter,
         registry: RegistryRepository,
         backupService: BackupService,
         startupError: AppError? = nil) {
        self.manager = manager
        self.router = router
        self.keyboard = keyboard
        self.registry = registry
        self.backupService = backupService
        self.shouldAutoOpenDemoCompany = ProcessInfo.processInfo.environment["AVELO_OPEN_DEMO"] == "1"
        self.startupError = startupError
    }

    private struct Stores {
        let manager: DatabaseManager
        let registryDb: SQLiteDatabase
    }

    /// Builds the database stores, tolerating failures of the normal
    /// Application Support location by degrading to a temporary directory.
    /// Returns any degradation as an `AppError` instead of crashing.
    private static func makeStores() -> (stores: Stores, error: AppError?) {
        // Tier 1: the normal Application Support location.
        if let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) {
            let dir = appSupport.appendingPathComponent("Avelo", isDirectory: true)
            if let stores = try? buildStores(in: dir) {
                return (stores, nil)
            }
        }

        // Tier 2: a unique temporary directory. Data will not persist across
        // launches, but the app stays usable and the user is told why.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Avelo-\(UUID().uuidString)", isDirectory: true)
        if let stores = try? buildStores(in: tempDir) {
            let msg = "Couldn't open Avelo's data folder, so a temporary location is being used. Any changes will NOT be saved when you quit. Check disk permissions and restart."
            return (stores, AppError.database(.openFailed(msg)))
        }

        // Tier 3: truly unrecoverable I/O environment. A clear, intentional
        // failure beats an opaque force-unwrap crash.
        preconditionFailure("Avelo could not create a database in either Application Support or a temporary directory. The filesystem is not writable.")
    }

    private static func buildStores(in aveloDir: URL) throws -> Stores {
        let manager = try DatabaseManager(appSupportDirectory: aveloDir)
        let registryDb = try SQLiteDatabase(path: manager.registryPath)
        return Stores(manager: manager, registryDb: registryDb)
    }

    public func bootstrap() async {
        // Directory creation + registry schema run inside DatabaseManager.init.
        // Surface any startup degradation now that the UI is live.
        if let startupError, globalError == nil {
            globalError = startupError
        }

        if shouldAutoOpenDemoCompany, companyContext == nil {
            do {
                try await ensureDemoCompanyOpen()
            } catch {
                globalError = AppError.wrap(error)
            }
        }
    }

    private func ensureDemoCompanyOpen() async throws {
        if let entry = try registry.listAll().first(where: { $0.name == "Demo Co" }) {
            await openCompany(entry.id)
            return
        }

        let company = try await CompanyService.create(
            companyInput: .init(
                name: "Demo Co",
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

        let dbURL = try await manager.companyFileURL(id: company.id)
        let db = try SQLiteDatabase(path: dbURL.path)
        defer { db.close() }

        let accounts = AccountService(db: db, companyId: company.id)
        let fyService = FinancialYearService(db: db, companyId: company.id)
        let vouchers = VoucherService(db: db, companyId: company.id)
        let inventory = InventoryService(db: db, companyId: company.id)
        let payroll = PayrollService(db: db, companyId: company.id)
        let banking = BankReconciliationService(db: db, companyId: company.id)
        let report = ReportService(db: db, companyId: company.id)

        guard let fy = try fyService.mostRecent() else {
            throw AppError.notFound("Financial year")
        }

        let groups = try accounts.listGroups()
        func group(_ code: String) throws -> AccountGroup {
            guard let g = groups.first(where: { $0.code == code }) else {
                throw AppError.notFound("Group \(code)")
            }
            return g
        }

        let currentAssets = try group("CURRENT_ASSETS")
        let currentLiabilities = try group("CURRENT_LIAB")
        let directIncome = try group("DIRECT_INCOME")
        let indirectExpense = try group("INDIRECT_EXPENSE")
        let cash = try accounts.listActiveAccounts().first(where: { $0.code == "CASH_IN_HAND" })!
        let bank = try accounts.listActiveAccounts().first(where: { $0.code == "BANK_HDFC" })!
        let sales = try accounts.listActiveAccounts().first(where: { $0.code == "SALES" })!
        let purchase = try accounts.listActiveAccounts().first(where: { $0.code == "PURCHASE" })!
        let salaryExpense = try accounts.listActiveAccounts().first(where: { $0.code == "SALARY_EXPENSE" })!

        let customer = try accounts.createAccount(.init(code: "CUST_DEMO", name: "Demo Customer", groupId: currentAssets.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let vendor = try accounts.createAccount(.init(code: "VEND_DEMO", name: "Demo Vendor", groupId: currentLiabilities.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        let consultingIncome = try accounts.createAccount(.init(code: "CONSULTING", name: "Consulting Income", groupId: directIncome.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        let travelExpense = try accounts.createAccount(.init(code: "TRAVEL_EXP", name: "Travel Expense", groupId: indirectExpense.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let salaryPayable = try accounts.createAccount(.init(code: "SAL_PAY", name: "Salary Payable Demo", groupId: currentLiabilities.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))

        let serviceInvoice = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-04-12")!, partyAccountId: customer.id, narration: "Demo consulting invoice", lines: [.init(accountId: customer.id, amountPaise: 125_000, side: .debit), .init(accountId: consultingIncome.id, amountPaise: 125_000, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .receipt, date: DateFormatters.parseDate("2024-04-14")!, partyAccountId: customer.id, narration: "Customer receipt", lines: [.init(accountId: cash.id, amountPaise: 125_000, side: .debit), .init(accountId: customer.id, amountPaise: 125_000, side: .credit)]), in: fy)
        let paymentVoucher = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .payment, date: DateFormatters.parseDate("2024-05-06")!, partyAccountId: vendor.id, narration: "Vendor payment by bank", lines: [.init(accountId: vendor.id, amountPaise: 58_000, side: .debit), .init(accountId: bank.id, amountPaise: 58_000, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-05-10")!, narration: "Salary provision", lines: [.init(accountId: salaryExpense.id, amountPaise: 42_500, side: .debit), .init(accountId: salaryPayable.id, amountPaise: 42_500, side: .credit)]), in: fy)
        _ = try vouchers.post(draft: VoucherDraft(mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-05-12")!, narration: "Travel reimbursement", lines: [.init(accountId: travelExpense.id, amountPaise: 9_500, side: .debit), .init(accountId: cash.id, amountPaise: 9_500, side: .credit)]), in: fy)

        let item = try inventory.createItem(code: "ITEM-001", name: "Demo Widget", unit: "Nos", openingQuantity: 40, openingRatePaise: 1_250, gstRate: 18, stockGroup: "Finished Goods", stockCategory: "Widgets", godown: "Main Store", barcode: "999000111222", hsnSac: "8471")
        try inventory.linkItemToAccount(itemId: item.id, accountId: sales.id)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-04-12")!, type: .opening, quantity: 20, ratePaise: 1_200, voucherId: serviceInvoice.voucher.id, notes: "Opening demo stock")
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-02")!, type: .sale, quantity: 8, ratePaise: 1_300, voucherId: serviceInvoice.voucher.id, notes: "Demo issue")

        let employee = try payroll.createEmployee(name: "Priya Shah", employeeCode: "EMP-001", designation: "Accounts Executive", pan: "ABCDE1234F", bankAccount: "123456789012", ifsc: "HDFC0001234", basicPaise: 28_000, hraPaise: 8_000, otherAllowancesPaise: 4_000, pfApplicable: true, esiApplicable: false)
        _ = try payroll.postEntry(employeeId: employee.id, monthYear: 202404, workingDays: 26, paidDays: 26, overtimePaise: 2_000, deductionsPaise: 1_500, financialYearId: fy.id)

        try banking.importStatement(accountId: bank.id, entries: [.init(id: UUID(), accountId: bank.id, date: DateFormatters.parseDate("2024-04-14")!, amountPaise: 125_000, narration: "Customer receipt", isCleared: false), .init(id: UUID(), accountId: bank.id, date: DateFormatters.parseDate("2024-05-06")!, amountPaise: -58_000, narration: "Vendor payment", isCleared: false)])
        _ = try banking.reconcile(accountId: bank.id, asOf: DateFormatters.parseDate("2024-05-31")!)
        try BankReconciliationRepository(db: db).upsert(.init(id: UUID(), companyId: company.id, bankAccountId: bank.id, voucherId: serviceInvoice.voucher.id, statementDate: DateFormatters.parseDate("2024-04-14")!, statementAmountPaise: 125_000, isCleared: true, clearedAt: Date(), note: "Auto-matched demo receipt"))
        try BankReconciliationRepository(db: db).upsert(.init(id: UUID(), companyId: company.id, bankAccountId: bank.id, voucherId: paymentVoucher.voucher.id, statementDate: DateFormatters.parseDate("2024-05-06")!, statementAmountPaise: -58_000, isCleared: true, clearedAt: Date(), note: "Demo payment clearing"))

        _ = try report.trialBalance(asOfDate: fy.endDate, financialYearId: fy.id)
        _ = try report.balanceSheet(asOfDate: fy.endDate, financialYearId: fy.id)
        _ = try report.profitAndLoss(fromDate: fy.startDate, toDate: fy.endDate, financialYearId: fy.id)
        _ = try report.dayBook(fromDate: fy.startDate, toDate: fy.endDate)
        _ = try report.ledger(accountId: cash.id, financialYearId: fy.id, fromDate: fy.startDate, toDate: fy.endDate)

        try await openCompany(company.id)
    }

    public func openCompany(_ id: Company.ID) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let handle = try await manager.openCompany(id: id)
            let fyRepo = FinancialYearRepository(db: handle.db)
            guard let fy = try fyRepo.findMostRecent(handle.companyId) else {
                throw AppError.notFound("Financial year for company \(id.uuidString)")
            }
            self.companyContext = CompanyContext(
                companyId: handle.companyId,
                companyName: handle.companyName,
                financialYear: fy,
                database: handle.db
            )
            self.accountTree = AccountTreeCache(companyId: handle.companyId, database: handle.db, financialYearId: fy.id)
            await self.accountTree?.reload()
            router.reset()
            banner = BannerPayload(kind: .success("Company opened."), message: "Company opened.")
        } catch {
            globalError = AppError.wrap(error)
        }
    }

    public func switchFinancialYear(_ id: FinancialYear.ID) {
        guard let ctx = companyContext else { return }
        do {
            guard let fy = try FinancialYearRepository(db: ctx.database).findById(id) else {
                throw AppError.notFound("Financial year")
            }
            companyContext = CompanyContext(
                companyId: ctx.companyId,
                companyName: ctx.companyName,
                financialYear: fy,
                database: ctx.database
            )
            accountTree = AccountTreeCache(companyId: ctx.companyId, database: ctx.database, financialYearId: fy.id)
            notifyDataChanged()
            Task { await self.accountTree?.reload() }
            banner = BannerPayload(kind: .info("Financial year switched."), message: "Financial year switched.")
        } catch {
            globalError = AppError.wrap(error)
        }
    }

    public func closeCompany() {
        if let ctx = companyContext {
            Task { await manager.closeCompany(id: ctx.companyId) }
        }
        companyContext = nil
        accountTree = nil
        router.reset()
    }

    public func markAccountTreeDirty() {
        accountTree?.invalidate()
    }

    public func notifyDataChanged() {
        dataRevision &+= 1
    }

    public func showError(_ error: AppError) {
        globalError = error
    }

    public func showInfo(_ message: String) {
        banner = BannerPayload(kind: .info(message), message: message)
    }

    public func showSuccess(_ message: String) {
        banner = BannerPayload(kind: .success(message), message: message)
    }

    public func clearBanner() {
        banner = nil
    }

    public var presentedSheetBinding: Binding<RouterSheet?> {
        Binding(
            get: { self.router.presentedSheet },
            set: { self.router.presentedSheet = $0 }
        )
    }
}

public struct CompanyContext: Sendable {
    public let companyId: Company.ID
    public let companyName: String
    public let financialYear: FinancialYear
    public let database: SQLiteDatabase

    public init(companyId: Company.ID, companyName: String, financialYear: FinancialYear, database: SQLiteDatabase) {
        self.companyId = companyId
        self.companyName = companyName
        self.financialYear = financialYear
        self.database = database
    }
}

public struct BannerPayload: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let kind: BannerKind
    public let message: String

    public init(kind: BannerKind, message: String) {
        self.kind = kind
        self.message = message
    }
}
