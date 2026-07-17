import Foundation

public struct MigrationV026: Migration {
    public let version: SchemaVersion = .v26
    public let description = "Add per-company saved workspace configurations"

    public init() {}

    /// Presentation metadata only (density, columns, filters-as-identifiers,
    /// print/export defaults). Deliberately no audit event on save: workspace
    /// configuration is not a financially meaningful mutation, and extending
    /// the CHECK-constrained audit action taxonomy requires rebuilding the
    /// audit table — not warranted for column widths.
    public func up(_ db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE avelo_workspace_configurations (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id) ON DELETE RESTRICT,
                workspace_id TEXT NOT NULL CHECK(length(trim(workspace_id)) > 0 AND length(workspace_id) <= 64),
                format_version INTEGER NOT NULL CHECK(format_version >= 1),
                payload_json TEXT NOT NULL CHECK(length(trim(payload_json)) > 0),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(company_id, workspace_id)
            );
            """
        )
        try db.execute("CREATE INDEX idx_avelo_workspace_configurations_company ON avelo_workspace_configurations(company_id);")
    }
}
