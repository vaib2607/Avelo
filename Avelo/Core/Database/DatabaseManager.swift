import Foundation
import os

private let AveloOpsLogger = Logger(subsystem: "com.avelo.desktop", category: "ops")

public final class CompanyHandle: @unchecked Sendable {
    public let companyId: Company.ID
    public let companyName: String
    public let db: SQLiteDatabase

    public init(companyId: Company.ID, companyName: String, db: SQLiteDatabase) {
        self.companyId = companyId
        self.companyName = companyName
        self.db = db
    }
}

public final actor DatabaseManager {

    public let appSupportDirectory: URL
    public let companiesDirectory: URL
    public let registryPath: String

    private var openHandles: [Company.ID: CompanyHandle] = [:]
    private var registryDb: SQLiteDatabase?

    public init(appSupportDirectory: URL) throws {
        self.appSupportDirectory = appSupportDirectory
        let companiesURL = appSupportDirectory.appendingPathComponent("Companies", isDirectory: true)
        self.companiesDirectory = companiesURL
        let registryURL = appSupportDirectory.appendingPathComponent("avelo_registry.sqlite")
        self.registryPath = registryURL.path

        let fm = FileManager.default
        try fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: companiesURL, withIntermediateDirectories: true)

        let reg = try SQLiteDatabase(path: registryURL.path)
        do {
            try reg.execute(Self.registrySchemaSQL)
        } catch {
            AveloOpsLogger.error("registry schema init failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        self.registryDb = reg
    }

    public static let registrySchemaSQL: String = #"""
    CREATE TABLE IF NOT EXISTS avelo_registry_companies (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        sqlite_file_name TEXT NOT NULL,
        last_opened_at TEXT,
        created_at TEXT NOT NULL,
        CHECK(length(trim(name)) > 0),
        CHECK(length(trim(sqlite_file_name)) > 0),
        UNIQUE(name),
        UNIQUE(sqlite_file_name)
    );
    CREATE INDEX IF NOT EXISTS idx_avelo_registry_name ON avelo_registry_companies(name);
    """#

    public func listCompanies() throws -> [CompanyRegistryEntry] {
        guard let reg = registryDb else { return [] }
        return try reg.query("SELECT id, name, sqlite_file_name, last_opened_at, created_at FROM avelo_registry_companies ORDER BY name COLLATE NOCASE") { row in
            let lastOpened: Date? = row.optionalText("last_opened_at").flatMap { DateFormatters.parseTimestamp($0) }
            return CompanyRegistryEntry(
                id: try UUIDParsing.required(row.text("id"), field: "avelo_registry_companies.id"),
                name: row.text("name"),
                sqliteFileName: row.text("sqlite_file_name"),
                lastOpenedAt: lastOpened,
                createdAt: try row.timestamp("created_at")
            )
        }
    }

    public func findCompany(id: UUID) throws -> CompanyRegistryEntry? {
        try listCompanies().first(where: { $0.id == id })
    }

    public func registerCompany(_ entry: CompanyRegistryEntry) throws {
        guard let reg = registryDb else { throw AppError.database(.openFailed("registry not open")) }
        try reg.execute(
            "INSERT OR REPLACE INTO avelo_registry_companies (id, name, sqlite_file_name, last_opened_at, created_at) VALUES (?, ?, ?, ?, ?)",
            [
                .text(entry.id.uuidString),
                .text(entry.name),
                .text(entry.sqliteFileName),
                .optionalTimestamp(entry.lastOpenedAt),
                .timestamp(entry.createdAt)
            ]
        )
    }

    public func unregisterCompany(id: UUID) throws {
        guard let reg = registryDb else { return }
        try reg.execute("DELETE FROM avelo_registry_companies WHERE id = ?", [.text(id.uuidString)])
    }

    public func touchLastOpened(id: UUID) throws {
        guard let reg = registryDb else { return }
        try reg.execute(
            "UPDATE avelo_registry_companies SET last_opened_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
    }

    public func createCompanyFile(companyId: UUID) throws -> URL {
        let url = companiesDirectory.appendingPathComponent("\(companyId.uuidString).sqlite")
        let db = try SQLiteDatabase(path: url.path)
        defer { db.close() }
        try MigrationRunner().runMigrations(on: db)
        return url
    }

    public func openCompany(id: UUID) throws -> CompanyHandle {
        if let existing = openHandles[id] { return existing }
        let url = try companyFileURL(id: id)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            throw AppError.notFound("Company file not found: \(url.lastPathComponent)")
        }
        let db = try SQLiteDatabase(path: url.path)
        let current = db.userVersion()
        if current < SchemaVersion.current.rawValue {
            do {
                try MigrationRunner().runMigrations(on: db)
            } catch {
                AveloOpsLogger.error("migration failed for company \(id.uuidString, privacy: .public)")
                throw error
            }
        }
        guard let reg = registryDb else {
            throw AppError.database(.openFailed("registry not open"))
        }
        guard let entry = try RegistryRepository(db: reg).findById(id) else {
            throw AppError.notFound("Registry entry missing for company \(id.uuidString)")
        }
        let handle = CompanyHandle(companyId: id, companyName: entry.name, db: db)
        openHandles[id] = handle
        try touchLastOpened(id: id)
        return handle
    }

    public func closeCompany(id: UUID) {
        if let handle = openHandles.removeValue(forKey: id) {
            handle.db.close()
        }
    }

    public func closeAll() {
        for (_, handle) in openHandles {
            handle.db.close()
        }
        openHandles.removeAll()
        registryDb?.close()
        registryDb = nil
    }

    public func openHandle(id: UUID) -> CompanyHandle? {
        openHandles[id]
    }

    public func companyFileURL(id: UUID) throws -> URL {
        let legacyURL = companiesDirectory.appendingPathComponent("\(id.uuidString).sqlite")
        let fm = FileManager.default

        guard let reg = registryDb else {
            return legacyURL
        }

        let entry = try RegistryRepository(db: reg).findById(id)
        guard let entry else {
            return legacyURL
        }

        let registeredURL = companiesDirectory.appendingPathComponent(entry.sqliteFileName)
        if fm.fileExists(atPath: registeredURL.path) {
            return registeredURL
        }
        if fm.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        throw AppError.notFound(
            "Company file missing. Expected \(entry.sqliteFileName). Re-link or restore the company file before opening it."
        )
    }

    public func deleteCompanyFiles(id: UUID) throws {
        closeCompany(id: id)
        let fm = FileManager.default
        let legacyURL = companiesDirectory.appendingPathComponent("\(id.uuidString).sqlite")
        let primaryURL = (try? companyFileURL(id: id)) ?? legacyURL
        let urls = Set([primaryURL, legacyURL])

        for url in urls {
            let walURL = URL(fileURLWithPath: url.path + "-wal")
            if fm.fileExists(atPath: walURL.path) {
                try fm.removeItem(at: walURL)
            }
            let shmURL = URL(fileURLWithPath: url.path + "-shm")
            if fm.fileExists(atPath: shmURL.path) {
                try fm.removeItem(at: shmURL)
            }
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }
}
