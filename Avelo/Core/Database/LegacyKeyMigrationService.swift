import Foundation
import os

private let AveloLegacyKeyMigrationLogger = Logger(subsystem: "com.avelo.desktop", category: "legacy-key-migration")

public struct LegacyKeyMigrationService: Sendable {
    public enum LegacySource: Sendable, Equatable {
        case plaintext
        case hardcodedPassphrase
    }

    public let keyStore: CompanyKeyStoring

    public init(keyStore: CompanyKeyStoring) {
        self.keyStore = keyStore
    }

    public func migrateIfNeeded(companyId: Company.ID, fileURL: URL) throws -> Data {
        if let existing = try keyStore.retrieve(companyId: companyId) {
            return existing
        }
        let source = try detectSource(fileURL: fileURL)
        let key = try keyStore.generateKey()
        try migrate(companyId: companyId, fileURL: fileURL, source: source, newKey: key)
        return key
    }

    public func detectSource(fileURL: URL) throws -> LegacySource {
        do {
            let db = try SQLiteDatabase(path: fileURL.path, readonly: true)
            defer { db.close() }
            _ = try db.queryOne("SELECT count(*) FROM sqlite_master") { $0.int(0) }
            return .plaintext
        } catch {
            do {
                let db = try SQLiteDatabase(
                    path: fileURL.path,
                    readonly: true,
                    encryptionKey: .passphrase(SQLiteDatabase.legacyHardcodedPassphrase)
                )
                defer { db.close() }
                _ = try db.queryOne("SELECT count(*) FROM sqlite_master") { $0.int(0) }
                return .hardcodedPassphrase
            } catch {
                throw AppError.database(.missingEncryptionKey("Company encryption key is missing and the file is not a supported legacy database."))
            }
        }
    }

    public func migrate(
        companyId: Company.ID,
        fileURL: URL,
        source: LegacySource,
        newKey: Data
    ) throws {
        let fm = FileManager.default
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".rekey-\(companyId.uuidString).sqlite")
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".pre-rekey-\(companyId.uuidString).sqlite")
        cleanup(url: tempURL)
        cleanup(url: backupURL)
        defer {
            cleanup(url: tempURL)
            cleanup(url: backupURL)
        }

        let sourceDb: SQLiteDatabase
        switch source {
        case .plaintext:
            sourceDb = try SQLiteDatabase(path: fileURL.path)
        case .hardcodedPassphrase:
            sourceDb = try SQLiteDatabase(
                path: fileURL.path,
                encryptionKey: .passphrase(SQLiteDatabase.legacyHardcodedPassphrase)
            )
        }
        defer { sourceDb.close() }

        try sourceDb.execute("ATTACH DATABASE ? AS encrypted KEY \"x'\(SQLiteDatabase.hex(newKey))'\"", [.text(tempURL.path)])
        try sourceDb.execute("SELECT sqlcipher_export('encrypted')")
        try sourceDb.execute("DETACH DATABASE encrypted")
        try sourceDb.checkpoint()

        let migrated = try SQLiteDatabase(path: tempURL.path, key: newKey)
        defer { migrated.close() }
        try verify(sourceDb: sourceDb, migratedDb: migrated)

        try fm.moveItem(at: fileURL, to: backupURL)
        do {
            try fm.moveItem(at: tempURL, to: fileURL)
            try keyStore.store(key: newKey, companyId: companyId)
            AveloLegacyKeyMigrationLogger.info("migrated legacy encrypted key for \(companyId.uuidString, privacy: .public)")
        } catch {
            if fm.fileExists(atPath: backupURL.path), !fm.fileExists(atPath: fileURL.path) {
                try? fm.moveItem(at: backupURL, to: fileURL)
            }
            throw error
        }
    }

    private func verify(sourceDb: SQLiteDatabase, migratedDb: SQLiteDatabase) throws {
        let sourceTables = try sourceDb.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") { $0.text(0) }
        let migratedTables = try migratedDb.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") { $0.text(0) }
        guard sourceTables == migratedTables else {
            throw AppError.database(.schemaMismatch("Legacy encryption migration changed the table list."))
        }
        for table in sourceTables {
            let sourceCount = try sourceDb.queryOne("SELECT COUNT(*) FROM \(table)") { $0.int(0) } ?? -1
            let migratedCount = try migratedDb.queryOne("SELECT COUNT(*) FROM \(table)") { $0.int(0) } ?? -2
            guard sourceCount == migratedCount else {
                throw AppError.database(.schemaMismatch("Legacy encryption migration changed row count for \(table)."))
            }
        }
    }

    private func cleanup(url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
