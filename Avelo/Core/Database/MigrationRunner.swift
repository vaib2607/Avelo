import Foundation

public protocol Migration: Sendable {
    var version: SchemaVersion { get }
    var description: String { get }
    func up(_ db: SQLiteDatabase) throws
}

public struct MigrationRunner: Sendable {

    public let migrations: [Migration]
    private let activityController: any LongOperationActivityControlling

    public init(migrations: [Migration] = MigrationRunner.defaultMigrations,
                activityController: any LongOperationActivityControlling = ProcessInfoLongOperationActivityController()) {
        self.migrations = migrations.sorted { $0.version.rawValue < $1.version.rawValue }
        self.activityController = activityController
    }

    public static let defaultMigrations: [Migration] = [
        MigrationV001(),
        MigrationV002(),
        MigrationV003(),
        MigrationV004(),
        MigrationV005(),
        MigrationV006(),
        MigrationV007(),
        MigrationV008(),
        MigrationV009(),
        MigrationV010(),
        MigrationV011(),
        MigrationV012(),
        MigrationV013(),
        MigrationV014(),
        MigrationV015(),
        MigrationV016(),
        MigrationV017(),
        MigrationV018(),
        MigrationV019(),
        MigrationV020(),
        MigrationV021(),
        MigrationV022(),
        MigrationV023(),
        MigrationV024(),
        MigrationV025()
    ]

    /// Applies every pending migration inside its own transaction (AVL-P0-015).
    ///
    /// - `onProgress` is called after each migration commits with
    ///   `(completed, total)`, where `total` is only the migrations actually
    ///   pending this run (not the full history), so callers can show real
    ///   progress instead of an indeterminate spinner on a large upgrade.
    /// - Cancellation is checked between migrations (never mid-migration,
    ///   since each one is already an atomic `db.write` transaction), so an
    ///   enclosing `Task` can interrupt a long run without leaving the schema
    ///   half-applied.
    /// - A failure is wrapped in `.migrationFailed` naming the specific
    ///   version and description, instead of surfacing a raw SQL error, so
    ///   the failure is actionable rather than cryptic.
    public func runMigrations(on db: SQLiteDatabase,
                              onProgress: ((_ completed: Int, _ total: Int) -> Void)? = nil) throws {
        try activityController.perform(reason: "Avelo database migration") {
            let current = try db.userVersion()
            let applied = try fetchAppliedVersions(db)
            let pending = migrations.filter { !applied.contains($0.version) && $0.version.rawValue >= current }
            let total = pending.count
            var completed = 0
            for migration in pending {
                try Task.checkCancellation()
                do {
                    try db.write { tx in
                        try migration.up(tx)
                        try insertMigrationRecord(tx, version: migration.version, description: migration.description)
                        try tx.setUserVersion(migration.version.rawValue)
                    }
                } catch {
                    throw AppError.database(.migrationFailed(
                        "Schema migration \(migration.version.rawValue) (\(migration.description)) failed: \(AppError.wrap(error).localizedMessage)"
                    ))
                }
                completed += 1
                onProgress?(completed, total)
            }
            let currentVersion = try db.userVersion()
            let recordedVersion = try fetchAppliedVersions(db).map(\.rawValue).max() ?? currentVersion
            if currentVersion < recordedVersion {
                try db.setUserVersion(recordedVersion)
            }
        }
    }

    private func fetchAppliedVersions(_ db: SQLiteDatabase) throws -> Set<SchemaVersion> {
        let exists: Int64? = try db.queryOne(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='avelo_migrations'"
        ) { r in r.int(0) }
        guard let exists, exists > 0 else { return [] }
        let versions: [Int64] = try db.query("SELECT version FROM avelo_migrations") { r in r.int(0) }
        var set = Set<SchemaVersion>()
        for v in versions {
            if let s = SchemaVersion(rawValue: Int(v)) { set.insert(s) }
        }
        return set
    }

    private func insertMigrationRecord(_ db: SQLiteDatabase, version: SchemaVersion, description: String) throws {
        try db.execute(
            "INSERT INTO avelo_migrations (version, applied_at, description) VALUES (?, ?, ?)",
            [
                .integer(Int64(version.rawValue)),
                .timestamp(Date()),
                .text(description)
            ]
        )
    }
}
