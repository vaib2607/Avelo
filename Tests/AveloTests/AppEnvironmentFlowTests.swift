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
