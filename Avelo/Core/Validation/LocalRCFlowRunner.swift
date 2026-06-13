import Foundation

@MainActor
enum LocalRCFlowRunner {

    struct Summary: Sendable {
        let companyName: String
        let createdAccountCode: String
        let trialBalanceBalanced: Bool
        let restoredTrialBalanceBalanced: Bool
    }

    static func run() async throws -> Summary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let restoreRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restoreRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: restoreRoot)
        }

        let manager = try DatabaseManager(appSupportDirectory: root)
        let restoreManager = try DatabaseManager(appSupportDirectory: restoreRoot)

        func requireDate(_ string: String) throws -> Date {
            guard let date = DateFormatters.parseDate(string) else {
                throw AppError.validation(.init(code: .internal, message: "Invalid date literal \(string)"))
            }
            return date
        }

        let company = try await CompanyService.create(
            companyInput: .init(name: "RC Accountant Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: try requireDate("2024-04-01"),
                endDate: try requireDate("2025-03-31"),
                booksBeginDate: try requireDate("2024-04-01")
            ),
            seedDefaults: true,
            manager: manager
        )

        let registryDb = try SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )
        await env.openCompany(company.id)

        guard let ctx = env.companyContext else {
            throw AppError.notFound("Expected company context after opening the created company")
        }

        let accountService = AccountService(db: ctx.database, companyId: ctx.companyId)
        let fyService = FinancialYearService(db: ctx.database, companyId: ctx.companyId)
        let voucherService = VoucherService(db: ctx.database, companyId: ctx.companyId)
        let reportService = ReportService(db: ctx.database, companyId: ctx.companyId)
        let companyService = CompanyService(db: ctx.database, companyId: ctx.companyId, manager: manager)

        try companyService.setInventoryMode(enabled: true, linkMode: .autoPrompt)

        let groups = try accountService.listGroups()
        guard let currentAssets = groups.first(where: { $0.code == "CURRENT_ASSETS" }) else {
            throw AppError.notFound("Current Assets group")
        }

        let partyAccount = try accountService.createAccount(.init(
            code: "CUST_RC",
            name: "RC Customer",
            groupId: currentAssets.id,
            openingBalancePaise: 0,
            openingBalanceSide: .debit,
            gstin: nil,
            existingAccountId: nil
        ))

        let seededAccounts = try accountService.listActiveAccounts()
        guard let cash = seededAccounts.first(where: { $0.code == "CASH_IN_HAND" || $0.name == "Cash-in-Hand" }) else {
            throw AppError.notFound("Cash-in-Hand account")
        }
        guard let sales = seededAccounts.first(where: { $0.code == "SALES" || $0.name == "Sales" }) else {
            throw AppError.notFound("Sales account")
        }
        guard let purchase = seededAccounts.first(where: { $0.code == "PURCHASE" || $0.name == "Purchase" }) else {
            throw AppError.notFound("Purchase account")
        }

        guard let fy = try fyService.mostRecent() else {
            throw AppError.notFound("Financial year")
        }

        let salesDraft = VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: try requireDate("2024-06-15"),
            partyAccountId: partyAccount.id,
            narration: "RC sales invoice",
            lines: [
                .init(accountId: partyAccount.id, amountPaise: 125_000, side: .debit),
                .init(accountId: sales.id, amountPaise: 125_000, side: .credit)
            ]
        )
        let postedSales = try voucherService.post(draft: salesDraft, in: fy)

        let editedSales = VoucherDraft(
            mode: .edit(originalVoucherId: postedSales.voucher.id),
            voucherTypeCode: .sales,
            date: try requireDate("2024-06-15"),
            partyAccountId: partyAccount.id,
            narration: "RC sales invoice revised",
            lines: [
                .init(accountId: partyAccount.id, amountPaise: 150_000, side: .debit),
                .init(accountId: sales.id, amountPaise: 150_000, side: .credit)
            ]
        )
        _ = try voucherService.edit(postedSales.voucher.id, with: editedSales, in: fy)

        let purchaseDraft = VoucherDraft(
            mode: .create,
            voucherTypeCode: .purchase,
            date: try requireDate("2024-06-16"),
            narration: "RC purchase voucher",
            lines: [
                .init(accountId: purchase.id, amountPaise: 40_000, side: .debit),
                .init(accountId: cash.id, amountPaise: 40_000, side: .credit)
            ]
        )
        _ = try voucherService.post(draft: purchaseDraft, in: fy)

        let trialBalance = try reportService.trialBalance(asOfDate: fy.endDate, financialYearId: fy.id)
        let totalDebits = trialBalance.rows.reduce(Int64(0)) { $0 + $1.debitPaise }
        let totalCredits = trialBalance.rows.reduce(Int64(0)) { $0 + $1.creditPaise }

        _ = try reportService.profitAndLoss(
            fromDate: fy.startDate,
            toDate: fy.endDate,
            financialYearId: fy.id
        )
        _ = try reportService.dayBook(fromDate: fy.startDate, toDate: fy.endDate)

        try fyService.lock(fy.id, reason: "RC lock check")
        do {
            _ = try voucherService.post(
                draft: VoucherDraft(
                    mode: .create,
                    voucherTypeCode: .receipt,
                    date: try requireDate("2024-06-20"),
                    narration: "Blocked by lock",
                    lines: [
                        .init(accountId: cash.id, amountPaise: 10_000, side: .debit),
                        .init(accountId: partyAccount.id, amountPaise: 10_000, side: .credit)
                    ]
                ),
                in: fy
            )
            throw AppError.businessRule("Locked FY allowed posting unexpectedly")
        } catch let AppError.validation(validation) where validation.code == .voucherFYLocked {
            // Expected.
        }

        let nextFY = try fyService.create(
            label: "2025-26",
            startDate: try requireDate("2025-04-01"),
            endDate: try requireDate("2026-03-31"),
            booksBeginDate: try requireDate("2025-04-01")
        )
        let reversal = try voucherService.reverse(postedSales.voucher.id, reason: "RC reversal")
        guard reversal.financialYearId == nextFY.id else {
            throw AppError.businessRule("Reversal did not land in the latest open FY")
        }

        let backupURL = root.appendingPathComponent("rc-accountant-flow.avelobackup")
        _ = try await BackupService(manager: manager).export(
            companyId: ctx.companyId,
            companyName: ctx.companyName,
            to: backupURL
        )

        let restored = try await RestoreService(manager: restoreManager).restore(from: backupURL)
        let restoredHandle = try await restoreManager.openCompany(id: restored.id)
        defer { Task { await restoreManager.closeCompany(id: restored.id) } }

        guard let restoredFY = try FinancialYearRepository(db: restoredHandle.db).findMostRecent(restored.id) else {
            throw AppError.notFound("Restored financial year")
        }
        let restoredReports = ReportService(db: restoredHandle.db, companyId: restored.id)
        let restoredTB = try restoredReports.trialBalance(asOfDate: restoredFY.endDate, financialYearId: restoredFY.id)
        let restoredDebits = restoredTB.rows.reduce(Int64(0)) { $0 + $1.debitPaise }
        let restoredCredits = restoredTB.rows.reduce(Int64(0)) { $0 + $1.creditPaise }

        let restoreAudit = try AuditRepository(db: restoredHandle.db).list(
            filter: .init(companyId: restored.id, action: .backupImported)
        )
        guard restoreAudit.count == 1 else {
            throw AppError.businessRule("Expected exactly one restore audit event")
        }

        return Summary(
            companyName: ctx.companyName,
            createdAccountCode: partyAccount.code,
            trialBalanceBalanced: totalDebits == totalCredits,
            restoredTrialBalanceBalanced: restoredDebits == restoredCredits
        )
    }
}
