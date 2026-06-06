import Foundation

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
        let registryURL = appSupportDirectory.appendingPathComponent("mally_registry.sqlite")
        self.registryPath = registryURL.path

        let fm = FileManager.default
        try fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: companiesURL, withIntermediateDirectories: true)

        let reg = try SQLiteDatabase(path: registryURL.path)
        try reg.execute(Self.registrySchemaSQL)
        self.registryDb = reg
    }

    public static let registrySchemaSQL: String = #"""
    CREATE TABLE IF NOT EXISTS mally_registry_companies (
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
    CREATE INDEX IF NOT EXISTS idx_mally_registry_name ON mally_registry_companies(name);
    """#

    public func listCompanies() throws -> [CompanyRegistryEntry] {
        guard let reg = registryDb else { return [] }
        return try reg.query("SELECT id, name, sqlite_file_name, last_opened_at, created_at FROM mally_registry_companies ORDER BY name COLLATE NOCASE") { row in
            let lastOpened: Date? = row.optionalText("last_opened_at").flatMap { DateFormatters.parseTimestamp($0) }
            return CompanyRegistryEntry(
                id: UUID(uuidString: row.text("id")) ?? UUID(),
                name: row.text("name"),
                sqliteFileName: row.text("sqlite_file_name"),
                lastOpenedAt: lastOpened,
                createdAt: row.timestamp("created_at")
            )
        }
    }

    public func findCompany(id: UUID) throws -> CompanyRegistryEntry? {
        try listCompanies().first(where: { $0.id == id })
    }

    public func registerCompany(_ entry: CompanyRegistryEntry) throws {
        guard let reg = registryDb else { throw AppError.database(.openFailed("registry not open")) }
        try reg.execute(
            "INSERT OR REPLACE INTO mally_registry_companies (id, name, sqlite_file_name, last_opened_at, created_at) VALUES (?, ?, ?, ?, ?)",
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
        try reg.execute("DELETE FROM mally_registry_companies WHERE id = ?", [.text(id.uuidString)])
    }

    public func touchLastOpened(id: UUID) throws {
        guard let reg = registryDb else { return }
        try reg.execute(
            "UPDATE mally_registry_companies SET last_opened_at = ? WHERE id = ?",
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
        let url = companiesDirectory.appendingPathComponent("\(id.uuidString).sqlite")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            throw AppError.notFound("Company file not found: \(url.lastPathComponent)")
        }
        let db = try SQLiteDatabase(path: url.path)
        let current = db.userVersion()
        if current < SchemaVersion.current.rawValue {
            try MigrationRunner().runMigrations(on: db)
        }
        let companyName: String
        if let reg = registryDb, let entry = try? RegistryRepository(db: reg).findById(id) {
            companyName = entry.name
        } else {
            companyName = ""
        }
        let handle = CompanyHandle(companyId: id, companyName: companyName, db: db)
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

    public func deleteCompanyFiles(id: UUID) throws {
        closeCompany(id: id)
        let url = companiesDirectory.appendingPathComponent("\(id.uuidString).sqlite")
        let wal = URL(fileURLWithPath: url.path + "-wal")
        let shm = URL(fileURLWithPath: url.path + "-shm")
        let fm = FileManager.default
        try? fm.removeItem(at: wal)
        try? fm.removeItem(at: shm)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
