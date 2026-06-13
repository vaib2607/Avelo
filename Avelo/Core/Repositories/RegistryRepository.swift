import Foundation

public struct RegistryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func listCompanies() throws -> [CompanyRegistryEntry] {
        try db.query(
            "SELECT id, name, sqlite_file_name, last_opened_at, created_at FROM avelo_registry_companies ORDER BY name COLLATE NOCASE"
        ) { r in
            let last = r.optionalText("last_opened_at").flatMap { DateFormatters.parseTimestamp($0) }
            return CompanyRegistryEntry(
                id: try UUIDParsing.required(r.text("id"), field: "avelo_registry_companies.id"),
                name: r.text("name"),
                sqliteFileName: r.text("sqlite_file_name"),
                lastOpenedAt: last,
                createdAt: try r.timestamp("created_at")
            )
        }
    }

    public func listAll() throws -> [CompanyRegistryEntry] { try listCompanies() }

    public func firstId(named name: String) throws -> Company.ID? {
        try listCompanies().first(where: { $0.name == name })?.id
    }

    public func findName(id: Company.ID) throws -> String? {
        try listCompanies().first(where: { $0.id == id })?.name
    }

    public func findById(_ id: Company.ID) throws -> CompanyRegistryEntry? {
        try listCompanies().first(where: { $0.id == id })
    }

    public func register(_ entry: CompanyRegistryEntry) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO avelo_registry_companies
            (id, name, sqlite_file_name, last_opened_at, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(entry.id.uuidString),
                .text(entry.name),
                .text(entry.sqliteFileName),
                .optionalTimestamp(entry.lastOpenedAt),
                .timestamp(entry.createdAt)
            ]
        )
    }

    public func unregister(id: Company.ID) throws {
        try db.execute(
            "DELETE FROM avelo_registry_companies WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    public func touchLastOpened(id: Company.ID) throws {
        try db.execute(
            "UPDATE avelo_registry_companies SET last_opened_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
    }
}
