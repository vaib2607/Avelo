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
            let last = try r.optionalTimestamp("last_opened_at")
            return CompanyRegistryEntry(
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_registry_companies.id"),
                name: try r.requiredText("name"),
                sqliteFileName: try r.requiredText("sqlite_file_name"),
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
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFileName = entry.sqliteFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = CompanyRegistryEntry(
            id: entry.id,
            name: trimmedName,
            sqliteFileName: trimmedFileName,
            lastOpenedAt: entry.lastOpenedAt,
            createdAt: entry.createdAt
        )

        guard !trimmedName.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "name", message: "Company name is required."))
        }
        guard !trimmedFileName.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "sqliteFileName", message: "SQLite file name is required."))
        }

        let existingById = try findById(normalized.id)
        if let existingByName = try findByName(trimmedName), existingByName.id != normalized.id {
            throw AppError.businessRule("A company named \"\(trimmedName)\" is already registered.")
        }
        if let existingByFile = try findBySQLiteFileName(trimmedFileName), existingByFile.id != normalized.id {
            throw AppError.businessRule("A company file named \"\(trimmedFileName)\" is already registered.")
        }

        if existingById == nil {
            try db.execute(
                """
                INSERT INTO avelo_registry_companies
                (id, name, sqlite_file_name, last_opened_at, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .text(normalized.id.uuidString),
                    .text(normalized.name),
                    .text(normalized.sqliteFileName),
                    .optionalTimestamp(normalized.lastOpenedAt),
                    .timestamp(normalized.createdAt)
                ]
            )
            return
        }

        try db.execute(
            """
            UPDATE avelo_registry_companies
            SET name = ?, sqlite_file_name = ?, last_opened_at = ?, created_at = ?
            WHERE id = ?
            """,
            [
                .text(normalized.name),
                .text(normalized.sqliteFileName),
                .optionalTimestamp(normalized.lastOpenedAt),
                .timestamp(normalized.createdAt),
                .text(normalized.id.uuidString)
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

    private func findByName(_ name: String) throws -> CompanyRegistryEntry? {
        try db.queryOne(
            """
            SELECT id, name, sqlite_file_name, last_opened_at, created_at
            FROM avelo_registry_companies
            WHERE name = ?
            LIMIT 1
            """,
            bind: [.text(name)]
        ) { r in
            let last = try r.optionalTimestamp("last_opened_at")
            return CompanyRegistryEntry(
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_registry_companies.id"),
                name: try r.requiredText("name"),
                sqliteFileName: try r.requiredText("sqlite_file_name"),
                lastOpenedAt: last,
                createdAt: try r.timestamp("created_at")
            )
        }
    }

    private func findBySQLiteFileName(_ sqliteFileName: String) throws -> CompanyRegistryEntry? {
        try db.queryOne(
            """
            SELECT id, name, sqlite_file_name, last_opened_at, created_at
            FROM avelo_registry_companies
            WHERE sqlite_file_name = ?
            LIMIT 1
            """,
            bind: [.text(sqliteFileName)]
        ) { r in
            let last = try r.optionalTimestamp("last_opened_at")
            return CompanyRegistryEntry(
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_registry_companies.id"),
                name: try r.requiredText("name"),
                sqliteFileName: try r.requiredText("sqlite_file_name"),
                lastOpenedAt: last,
                createdAt: try r.timestamp("created_at")
            )
        }
    }
}
