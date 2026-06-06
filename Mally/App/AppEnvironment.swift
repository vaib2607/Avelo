import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {

    @Published public var companyContext: CompanyContext?
    @Published public var globalError: AppError?
    @Published public var banner: BannerPayload?
    @Published public var isBusy: Bool = false

    public let manager: DatabaseManager
    public let router: AppRouter
    public let registry: RegistryRepository
    public let backupService: BackupService

    public init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let mallyDir = appSupport.appendingPathComponent("Mally", isDirectory: true)
        let companiesDir = mallyDir.appendingPathComponent("Companies", isDirectory: true)
        let registryPath = mallyDir.appendingPathComponent("mally_registry.sqlite").path
        let backupDir = mallyDir.appendingPathComponent("Backups", isDirectory: true)
        self.manager = DatabaseManager(
            companiesDirectory: companiesDir,
            registryPath: registryPath,
            backupDirectory: backupDir
        )
        self.router = AppRouter()
        let registryDb = try! SQLiteDatabase(path: registryPath)
        self.registry = RegistryRepository(db: registryDb)
        self.backupService = BackupService(manager: manager, backupDirectory: backupDir)
    }

    public func bootstrap() async {
        do {
            try await manager.ensureDirectories()
            try manager.runMigrationsIfNeeded()
            try await manager.ensureRegistry()
        } catch {
            self.globalError = AppError.wrap(error)
        }
    }

    public func openCompany(_ id: Company.ID) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let ctx = try await manager.openHandle(id: id)
            self.companyContext = ctx
            router.reset()
            banner = BannerPayload(kind: .success, message: "Company opened.")
        } catch {
            globalError = AppError.wrap(error)
        }
    }

    public func closeCompany() {
        companyContext = nil
        router.reset()
    }

    public func showError(_ error: AppError) {
        globalError = error
    }

    public func showInfo(_ message: String) {
        banner = BannerPayload(kind: .info, message: message)
    }

    public func showSuccess(_ message: String) {
        banner = BannerPayload(kind: .success, message: message)
    }

    public func clearBanner() {
        banner = nil
    }
}

public struct CompanyContext: Sendable {
    public let companyId: Company.ID
    public let financialYear: FinancialYear
    public let database: SQLiteDatabase

    public init(companyId: Company.ID, financialYear: FinancialYear, database: SQLiteDatabase) {
        self.companyId = companyId
        self.financialYear = financialYear
        self.database = database
    }
}

public struct BannerPayload: Identifiable, Sendable {
    public let id = UUID()
    public let kind: BannerKind
    public let message: String
}
