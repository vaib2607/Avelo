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

    @MainActor
    public init() {
        self.router = AppRouter()
        self.keyboard = KeyboardRouter()

        let bootstrap = AppEnvironment.makeStores()
        self.manager = bootstrap.stores.manager
        self.registry = RegistryRepository(db: bootstrap.stores.registryDb)
        self.backupService = BackupService(manager: bootstrap.stores.manager)
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
            self.accountTree = AccountTreeCache(companyId: handle.companyId, database: handle.db)
            self.accountTree?.reload()
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
            notifyDataChanged()
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
