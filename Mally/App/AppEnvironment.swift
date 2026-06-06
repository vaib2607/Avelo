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
        let registryPath = mallyDir.appendingPathComponent("mally_registry.sqlite").path
        let backupDir = mallyDir.appendingPathComponent("Backups", isDirectory: true)

        self.manager = try! DatabaseManager(appSupportDirectory: mallyDir)
        self.router = AppRouter()

        let registryDb = try! SQLiteDatabase(path: registryPath)
        self.registry = RegistryRepository(db: registryDb)
        self.backupService = BackupService(manager: manager)
    }

    public func bootstrap() async {
        // Directory creation + registry schema run inside DatabaseManager.init.
        // Nothing to do here; kept as a hook for future one-time setup.
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
            router.reset()
            banner = BannerPayload(kind: .success("Company opened."), message: "Company opened.")
        } catch {
            globalError = AppError.wrap(error)
        }
    }

    public func closeCompany() {
        if let ctx = companyContext {
            Task { await manager.closeCompany(id: ctx.companyId) }
        }
        companyContext = nil
        router.reset()
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
