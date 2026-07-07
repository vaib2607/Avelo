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
        MigrationV017()
    ]

    public func runMigrations(on db: SQLiteDatabase) throws {
        try activityController.perform(reason: "Avelo database migration") {
            let current = try db.userVersion()
            let applied = try fetchAppliedVersions(db)
            for migration in migrations {
                if applied.contains(migration.version) { continue }
                if migration.version.rawValue < current { continue }
                try db.write { tx in
                    try migration.up(tx)
                    try insertMigrationRecord(tx, version: migration.version, description: migration.description)
                    try tx.setUserVersion(migration.version.rawValue)
                }
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
