import XCTest
@testable import Avelo

@MainActor
final class AppEnvironmentFlowTests: XCTestCase {

    func testBootstrapSurfacesStartupDegradationAsGlobalError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let startupError = AppError.database(.openFailed("Temporary data location in use"))
        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager),
            startupError: startupError
        )

        await env.bootstrap()

        XCTAssertEqual(env.globalError?.id, startupError.id)
        XCTAssertEqual(env.globalError?.localizedMessage, startupError.localizedMessage)
    }

    func testOpenCompanyAfterCreateSetsUsableContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )

        let company = try await CompanyService.create(
            companyInput: .init(name: "Flow Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )

        await env.openCompany(company.id)

        let ctx = try XCTUnwrap(env.companyContext)
        XCTAssertEqual(ctx.companyId, company.id)
        XCTAssertEqual(ctx.companyName, "Flow Co")
        XCTAssertEqual(ctx.financialYear.label, "2024-25")
        XCTAssertNotNil(env.accountTree)
        XCTAssertEqual(env.accountTree?.companyId, company.id)
        XCTAssertEqual(env.router.selection, .dashboard)
        XCTAssertNil(env.router.presentedSheet)
        XCTAssertEqual(env.banner?.message, "Company opened.")
        let openEvents = try AuditRepository(db: ctx.database).list(
            filter: .init(companyId: company.id, action: .companySwitched)
        )
        XCTAssertEqual(openEvents.count, 1)
        XCTAssertEqual(openEvents.first?.entityId, company.id.uuidString)
        XCTAssertNotNil(openEvents.first?.reason)
    }

    func testFinancialYearSwitchIsAuditedBeforeVisibleContextChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }
        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )
        let company = try await CompanyService.create(
            companyInput: .init(name: "FY Switch Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        await env.openCompany(company.id)
        let initial = try XCTUnwrap(env.companyContext)
        let next = try FinancialYearService(db: initial.database, companyId: company.id).create(
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )

        env.switchFinancialYear(next.id)

        XCTAssertEqual(env.companyContext?.financialYear.id, next.id)
        let events = try AuditRepository(db: initial.database).list(
            filter: .init(companyId: company.id, action: .financialYearSwitched)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.entityId, next.id.uuidString)
        XCTAssertNotNil(events.first?.reason)
    }

    // Unit E / multi-window investigation, 2026-07-16: two independent
    // AppEnvironment/DatabaseManager pairs against the same app-support
    // root (matching what two real windows would produce) previously
    // failed here — envB.openCompany(beta.id) didn't resolve to beta's own
    // context. Root cause: CompanyService.create wrote the registry row
    // through a freshly-opened SQLiteDatabase on the registry file instead
    // of DatabaseManager's own long-lived registryDb connection, so a
    // second manager's registry reads could race the first manager's
    // out-of-band write. Fixed by routing the write through
    // DatabaseManager.registerCompany(_:), the actor's own connection.
    func testTwoIndependentEnvironmentsOnSharedStorageDoNotLeakCompanyContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let managerA = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDbA = try await SQLiteDatabase(path: managerA.registryPath)
        defer { registryDbA.close() }
        let envA = AppEnvironment(
            manager: managerA,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDbA),
            backupService: BackupService(manager: managerA)
        )

        let managerB = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDbB = try await SQLiteDatabase(path: managerB.registryPath)
        defer { registryDbB.close() }
        let envB = AppEnvironment(
            manager: managerB,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDbB),
            backupService: BackupService(manager: managerB)
        )

        let alpha = try await CompanyService.create(
            companyInput: .init(name: "Window Alpha Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: managerA
        )
        let beta = try await CompanyService.create(
            companyInput: .init(name: "Window Beta Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: managerB
        )

        await envA.openCompany(alpha.id)
        await envB.openCompany(beta.id)

        let ctxA = try XCTUnwrap(envA.companyContext)
        let ctxB = try XCTUnwrap(envB.companyContext)
        XCTAssertEqual(ctxA.companyId, alpha.id)
        XCTAssertEqual(ctxA.companyName, "Window Alpha Co")
        XCTAssertEqual(ctxB.companyId, beta.id)
        XCTAssertEqual(ctxB.companyName, "Window Beta Co")
        XCTAssertNotEqual(ctxA.companyId, ctxB.companyId)
    }

    func testOpeningSecondCompanyResetsRouterAndSwapsVisibleContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )

        let alpha = try await CompanyService.create(
            companyInput: .init(name: "Alpha Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        let beta = try await CompanyService.create(
            companyInput: .init(name: "Beta Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2025-26",
                startDate: DateFormatters.parseDate("2025-04-01")!,
                endDate: DateFormatters.parseDate("2026-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2025-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )

        await env.openCompany(alpha.id)
        let firstTree = env.accountTree
        env.router.selection = .reports
        env.router.present(.newVoucher)

        await env.openCompany(beta.id)

        let ctx = try XCTUnwrap(env.companyContext)
        XCTAssertEqual(ctx.companyId, beta.id)
        XCTAssertEqual(ctx.companyName, "Beta Co")
        XCTAssertEqual(ctx.financialYear.label, "2025-26")
        XCTAssertEqual(env.accountTree?.companyId, beta.id)
        XCTAssertNotIdentical(env.accountTree, firstTree)
        XCTAssertEqual(env.router.selection, .dashboard)
        XCTAssertNil(env.router.presentedSheet)
        XCTAssertEqual(env.banner?.message, "Company opened.")
    }

    func testEnvironmentCanOpenRestoredCompanyIntoUsableContext() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceManager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let sourceCompany = try await CompanyService.create(
            companyInput: .init(name: "Restore Flow Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: sourceManager
        )

        let backupURL = sourceRoot.appendingPathComponent("restore-flow.avelobackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: "Restore Flow Co",
            to: backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        let targetRegistryPath = await targetManager.registryPath
        let targetRegistryDb = try SQLiteDatabase(path: targetRegistryPath)
        defer { targetRegistryDb.close() }

        let env = AppEnvironment(
            manager: targetManager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: targetRegistryDb),
            backupService: BackupService(manager: targetManager)
        )

        let restored = try await RestoreService(manager: targetManager).restore(
            from: backupURL,
            recoveryKey: try sourceManager.recoveryKey(for: sourceCompany.id)
        )
        await env.openCompany(restored.id)

        let ctx = try XCTUnwrap(env.companyContext)
        XCTAssertEqual(ctx.companyId, restored.id)
        XCTAssertEqual(ctx.companyName, "Restore Flow Co")
        XCTAssertEqual(ctx.financialYear.label, "2024-25")
        XCTAssertEqual(env.accountTree?.companyId, restored.id)
        XCTAssertEqual(env.router.selection, .dashboard)
        XCTAssertNil(env.router.presentedSheet)
    }

    func testCompanySwitchSoakMaintainsCorrectContextAcrossRepeatedOpens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )

        let alpha = try await CompanyService.create(
            companyInput: .init(name: "Soak Alpha", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        let beta = try await CompanyService.create(
            companyInput: .init(name: "Soak Beta", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2025-26",
                startDate: DateFormatters.parseDate("2025-04-01")!,
                endDate: DateFormatters.parseDate("2026-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2025-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )

        for index in 0..<100 {
            let target = index.isMultiple(of: 2) ? alpha : beta
            await env.openCompany(target.id)

            let ctx = try XCTUnwrap(env.companyContext)
            XCTAssertEqual(ctx.companyId, target.id)
            XCTAssertEqual(env.accountTree?.companyId, target.id)
            XCTAssertEqual(env.router.selection, .dashboard)
            XCTAssertNil(env.router.presentedSheet)
            XCTAssertEqual(env.banner?.message, "Company opened.")
        }
    }

    func testCloseCompanyClearsVisibleContextAndRouterState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )

        let company = try await CompanyService.create(
            companyInput: .init(name: "Close Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )

        await env.openCompany(company.id)
        env.router.selection = .reports
        env.router.present(.newVoucher)

        env.closeCompany()

        XCTAssertNil(env.companyContext)
        XCTAssertNil(env.accountTree)
        XCTAssertEqual(env.router.selection, .dashboard)
        XCTAssertNil(env.router.presentedSheet)
    }

    func testDeleteNonOpenCompanyRemovesFilesAndRegistryEntry() async throws {
        let fixture = try await makeEnvironmentFixture()
        defer { fixture.cleanup() }

        let company = try await makeCompany(named: "Delete Non Open Co", manager: fixture.manager)
        let dbURL = try await fixture.manager.companyFileURL(id: company.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))

        await fixture.env.deleteCompany(company.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        XCTAssertNil(try fixture.registry.findById(company.id))
        XCTAssertNil(fixture.env.companyContext)
        XCTAssertFalse(fixture.env.isBusy)
        XCTAssertEqual(fixture.env.banner?.message, "Company deleted.")
    }

    func testDeleteOpenCompanyClearsContextAndRouterState() async throws {
        let fixture = try await makeEnvironmentFixture()
        defer { fixture.cleanup() }

        let company = try await makeCompany(named: "Delete Open Co", manager: fixture.manager)
        let dbURL = try await fixture.manager.companyFileURL(id: company.id)
        await fixture.env.openCompany(company.id)
        fixture.env.router.selection = .reports
        fixture.env.router.present(.newVoucher)

        await fixture.env.deleteCompany(company.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        XCTAssertNil(try fixture.registry.findById(company.id))
        XCTAssertNil(fixture.env.companyContext)
        XCTAssertNil(fixture.env.accountTree)
        XCTAssertEqual(fixture.env.router.selection, .dashboard)
        XCTAssertNil(fixture.env.router.presentedSheet)
        XCTAssertFalse(fixture.env.isBusy)
    }

    func testDeleteCompanyConfirmationCancelAbortsWithoutStartingAction() throws {
        let companyId = UUID()
        var rowActions = OpenCompanyRowActionState()

        rowActions.requestDelete(companyId)
        XCTAssertEqual(rowActions.pendingDeleteCompanyId, companyId)

        rowActions.cancelDelete()

        XCTAssertNil(rowActions.pendingDeleteCompanyId)
        XCTAssertNil(rowActions.activeAction)
        XCTAssertFalse(rowActions.beginDelete(companyId, appIsBusy: false))
    }

    func testDemoBootstrapDoesNotForceCrashWhenExpectedSeedAccountsAreMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let registryDb = try await SQLiteDatabase(path: manager.registryPath)
        defer { registryDb.close() }

        let env = AppEnvironment(
            manager: manager,
            router: AppRouter(),
            keyboard: KeyboardRouter(),
            registry: RegistryRepository(db: registryDb),
            backupService: BackupService(manager: manager)
        )

        env.onDemoCompanyCreatedForTesting = { companyId in
            let dbURL = try await manager.companyFileURL(id: companyId)
            guard let key = try manager.keyStore.retrieve(companyId: companyId) else {
                throw AppError.database(.missingEncryptionKey("Company encryption key is missing."))
            }
            let db = try SQLiteDatabase(path: dbURL.path, key: key)
            defer { db.close() }
            try tcLikeDeleteAccountCodeIfExists(db: db, code: "PURCHASE")
        }

        do {
            try await env.ensureDemoCompanyOpenForTesting()
            XCTFail("Expected missing seed account to be reported as a notFound error")
        } catch {
            guard case AppError.notFound(let message) = AppError.wrap(error) else {
                return XCTFail("Expected notFound error, got \(error)")
            }
            XCTAssertEqual(message, "Seed account PURCHASE")
        }
    }
}

private func tcLikeDeleteAccountCodeIfExists(db: SQLiteDatabase, code: String) throws {
    _ = try db.execute(
        "DELETE FROM avelo_accounts WHERE code = ?",
        [.text(code)]
    )
}

@MainActor
private struct AppEnvironmentTestFixture {
    let root: URL
    let manager: DatabaseManager
    let registryDb: SQLiteDatabase
    let registry: RegistryRepository
    let env: AppEnvironment

    func cleanup() {
        registryDb.close()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func makeEnvironmentFixture() async throws -> AppEnvironmentTestFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
    let registryDb = try await SQLiteDatabase(path: manager.registryPath)
    let registry = RegistryRepository(db: registryDb)
    let env = AppEnvironment(
        manager: manager,
        router: AppRouter(),
        keyboard: KeyboardRouter(),
        registry: registry,
        backupService: BackupService(manager: manager)
    )
    return AppEnvironmentTestFixture(root: root, manager: manager, registryDb: registryDb, registry: registry, env: env)
}

private func makeCompany(named name: String, manager: DatabaseManager) async throws -> Company {
    try await CompanyService.create(
        companyInput: .init(name: name, gstin: nil, pan: nil),
        fyInput: .init(
            label: "2024-25",
            startDate: DateFormatters.parseDate("2024-04-01")!,
            endDate: DateFormatters.parseDate("2025-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2024-04-01")!
        ),
        seedDefaults: true,
        manager: manager
    )
}
