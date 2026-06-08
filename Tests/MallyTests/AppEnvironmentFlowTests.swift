import XCTest
@testable import Mally

@MainActor
final class AppEnvironmentFlowTests: XCTestCase {

    func testOpenCompanyAfterCreateSetsUsableContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
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

        let manager = try DatabaseManager(appSupportDirectory: root)
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

        let sourceManager = try DatabaseManager(appSupportDirectory: sourceRoot)
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

        let backupURL = sourceRoot.appendingPathComponent("restore-flow.mallybackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: "Restore Flow Co",
            to: backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot)
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

        let restored = try await RestoreService(manager: targetManager).restore(from: backupURL)
        await env.openCompany(restored.id)

        let ctx = try XCTUnwrap(env.companyContext)
        XCTAssertEqual(ctx.companyId, restored.id)
        XCTAssertEqual(ctx.companyName, "Restore Flow Co")
        XCTAssertEqual(ctx.financialYear.label, "2024-25")
        XCTAssertEqual(env.accountTree?.companyId, restored.id)
        XCTAssertEqual(env.router.selection, .dashboard)
        XCTAssertNil(env.router.presentedSheet)
    }
}
