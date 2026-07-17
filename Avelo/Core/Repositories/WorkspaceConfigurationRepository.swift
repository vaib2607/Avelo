import Foundation

public struct WorkspaceConfigurationRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    /// Returns nil for missing rows, rows written by a newer app (format
    /// version above the current one), or rows whose payload no longer
    /// decodes/validates — a stale saved view must never block opening the
    /// workspace it belongs to.
    public func find(companyId: Company.ID, workspaceId: WorkspaceIdentifier) throws -> WorkspaceConfiguration? {
        let row = try db.queryOne(
            """
            SELECT format_version, payload_json
            FROM avelo_workspace_configurations
            WHERE company_id = ? AND workspace_id = ?
            """,
            bind: [.text(companyId.uuidString), .text(workspaceId.rawValue)],
            row: { row in
                (version: try row.requiredInt("format_version"), payload: try row.requiredText("payload_json"))
            }
        )
        guard let row, row.version <= Int64(WorkspaceConfiguration.currentFormatVersion) else { return nil }
        guard let data = row.payload.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(WorkspaceConfiguration.self, from: data),
              configuration.hasValidIdentifiers else { return nil }
        return configuration
    }

    public func save(_ configuration: WorkspaceConfiguration, companyId: Company.ID, workspaceId: WorkspaceIdentifier) throws {
        guard configuration.hasValidIdentifiers else {
            throw AppError.validation(.init(code: .internal, field: "workspaceConfiguration", message: "Workspace configuration contains an invalid field identifier."))
        }
        let payload = String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
        let now = Date()
        try db.execute(
            """
            INSERT INTO avelo_workspace_configurations
            (id, company_id, workspace_id, format_version, payload_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(company_id, workspace_id) DO UPDATE SET
                format_version = excluded.format_version,
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at
            """,
            [
                .text(UUID().uuidString),
                .text(companyId.uuidString),
                .text(workspaceId.rawValue),
                .integer(Int64(configuration.formatVersion)),
                .text(payload),
                .timestamp(now),
                .timestamp(now)
            ]
        )
    }

    public func delete(companyId: Company.ID, workspaceId: WorkspaceIdentifier) throws {
        try db.execute(
            "DELETE FROM avelo_workspace_configurations WHERE company_id = ? AND workspace_id = ?",
            [.text(companyId.uuidString), .text(workspaceId.rawValue)]
        )
    }
}
