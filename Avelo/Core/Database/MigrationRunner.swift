import Foundation

public protocol Migration: Sendable {
    var version: SchemaVersion { get }
    var description: String { get }
    func up(_ db: SQLiteDatabase) throws
}

public struct MigrationRunner: Sendable {

    public let migrations: [Migration]

    public init(migrations: [Migration] = MigrationRunner.defaultMigrations) {
        self.migrations = migrations.sorted { $0.version.rawValue < $1.version.rawValue }
    }

    public static let defaultMigrations: [Migration] = [
        MigrationV001(),
        MigrationV002(),
        MigrationV003(),
        MigrationV004()
    ]

    public func runMigrations(on db: SQLiteDatabase) throws {
        let current = db.userVersion()
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
        let recordedVersion = try fetchAppliedVersions(db).map(\.rawValue).max() ?? db.userVersion()
        if db.userVersion() < recordedVersion {
            try db.setUserVersion(recordedVersion)
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
