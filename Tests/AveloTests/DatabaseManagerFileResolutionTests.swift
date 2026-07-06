import XCTest
@testable import Avelo

final class DatabaseManagerFileResolutionTests: XCTestCase {

    func testConcurrentOpenCompanyCreatesOnlyOneDatabaseHandle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let counter = DatabaseOpenCounter()
        let manager = try DatabaseManager(
            appSupportDirectory: root,
            keyStore: InMemoryCompanyKeyStore(),
            databaseOpener: { path, key in
                counter.increment()
                return try SQLiteDatabase(path: path, key: key)
            }
        )
        let companyId = UUID()
        let companyURL = try await manager.createCompanyFile(companyId: companyId)
        counter.reset()

        let companyKey = try XCTUnwrap(try manager.keyStore.retrieve(companyId: companyId))
        let db = try SQLiteDatabase(path: companyURL.path, key: companyKey)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Concurrent Open Co")
        db.close()
        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Concurrent Open Co", sqliteFileName: companyURL.lastPathComponent)
        )

        let handles = try await withThrowingTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let handle = try await manager.openCompany(id: companyId)
                    return ObjectIdentifier(handle)
                }
            }
            var identifiers: [ObjectIdentifier] = []
            for try await identifier in group {
                identifiers.append(identifier)
            }
            return identifiers
        }

        XCTAssertEqual(Set(handles).count, 1)
        XCTAssertEqual(counter.value, 1)
    }

    func testOpenCompanyUsesRegistrySQLiteFileNameWhenItDiffersFromLegacyPattern() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let companyName = "Registry Path Co"
        let actualURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("restored-company.sqlite")

        let db = try SQLiteDatabase(path: actualURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: companyName)
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: companyName, sqliteFileName: actualURL.lastPathComponent)
        )

        let handle = try await manager.openCompany(id: companyId)
        defer { Task { await manager.closeCompany(id: companyId) } }

        XCTAssertEqual(handle.companyId, companyId)
        XCTAssertEqual(handle.companyName, companyName)
        let company = try XCTUnwrap(CompanyRepository(db: handle.db).findById(companyId))
        XCTAssertEqual(company.name, companyName)
    }

    func testOpenCompanyFailsClearlyWhenRegisteredFileIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Missing File Co", sqliteFileName: "missing-company.sqlite")
        )

        do {
            _ = try await manager.openCompany(id: companyId)
            XCTFail("Expected openCompany to fail for missing registered file")
        } catch {
            guard case AppError.notFound(let message) = AppError.wrap(error) else {
                return XCTFail("Expected notFound error, got \(error)")
            }
            XCTAssertTrue(message.contains("missing-company.sqlite"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("re-link") || message.localizedCaseInsensitiveContains("restore"))
        }
    }

    func testOpenCompanyFailsClearlyWhenRegistryEntryIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let legacyURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")

        let db = try SQLiteDatabase(path: legacyURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Registry Missing Co")
        db.close()

        do {
            _ = try await manager.openCompany(id: companyId)
            XCTFail("Expected openCompany to fail when the registry entry is missing")
        } catch {
            guard case AppError.notFound(let message) = AppError.wrap(error) else {
                return XCTFail("Expected notFound error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("registry entry missing"))
        }
    }

    func testOpenCompanyRejectsTamperedAuditChain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyStore = InMemoryCompanyKeyStore()
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: keyStore)
        let companyId = UUID()
        let companyURL = try await manager.createCompanyFile(companyId: companyId)

        let companyKey = try XCTUnwrap(try keyStore.retrieve(companyId: companyId))
        let db = try SQLiteDatabase(path: companyURL.path, key: companyKey)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Tampered Audit Co")
        let audit = AuditService(db: db, companyId: companyId)
        try audit.record(action: .accountCreated, entityType: "account", entityId: "A-1", reason: "before tamper")
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Tampered Audit Co", sqliteFileName: companyURL.lastPathComponent)
        )

        let tamperDB = try SQLiteDatabase(path: companyURL.path, key: companyKey)
        try tamperDB.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_update")
        try tamperDB.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_delete")
        try tamperDB.execute("UPDATE avelo_audit_events SET reason = 'tampered' WHERE company_id = ?", [.text(companyId.uuidString)])
        tamperDB.close()

        do {
            _ = try await manager.openCompany(id: companyId)
            XCTFail("Expected tampered audit chain to block openCompany")
        } catch {
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected businessRule tamper error, got \(error)")
            }
            XCTAssertTrue(message.contains("Audit chain verification failed"))
        }
    }

    func testBackupExportUsesRegisteredSQLiteFileName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let sourceURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("custom-export-source.sqlite")

        let db = try SQLiteDatabase(path: sourceURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Backup Path Co")
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Backup Path Co", sqliteFileName: sourceURL.lastPathComponent)
        )

        let destinationURL = root.appendingPathComponent("backup-output.avelobackup")
        let manifest = try await BackupService(manager: manager).export(
            companyId: companyId,
            companyName: "Backup Path Co",
            to: destinationURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(manifest.originalFileName, sourceURL.lastPathComponent)
    }

    func testBackupExportFailsClearlyWhenDestinationDirectoryIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let sourceURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("backup-source.sqlite")

        let db = try SQLiteDatabase(path: sourceURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Backup Failure Co")
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Backup Failure Co", sqliteFileName: sourceURL.lastPathComponent)
        )

        let destinationURL = root
            .appendingPathComponent("missing-output-dir", isDirectory: true)
            .appendingPathComponent("backup-output.avelobackup")

        do {
            _ = try await BackupService(manager: manager).export(
                companyId: companyId,
                companyName: "Backup Failure Co",
                to: destinationURL
            )
            XCTFail("Expected backup export to fail for a missing destination directory")
        } catch {
            guard case AppError.fileSystem(let message) = AppError.wrap(error) else {
                return XCTFail("Expected fileSystem error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("backup file"))
        }
    }

    func testBackupExportFailsClearlyWhenExistingDestinationCannotBeReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let sourceURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("backup-source.sqlite")

        let db = try SQLiteDatabase(path: sourceURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Backup Replace Failure Co")
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Backup Replace Failure Co", sqliteFileName: sourceURL.lastPathComponent)
        )

        let lockedDirectory = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        let destinationURL = lockedDirectory.appendingPathComponent("existing-backup.avelobackup")
        try Data("keep".utf8).write(to: destinationURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDirectory.path)

        do {
            _ = try await BackupService(manager: manager).export(
                companyId: companyId,
                companyName: "Backup Replace Failure Co",
                to: destinationURL
            )
            XCTFail("Expected backup export to fail when an existing directory blocks replacement")
        } catch {
            guard case AppError.fileSystem(let message) = AppError.wrap(error) else {
                return XCTFail("Expected fileSystem error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("backup file"))
        }
    }

    func testDeleteCompanyFilesRemovesRegisteredAndLegacyFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let companiesURL = root.appendingPathComponent("Companies", isDirectory: true)
        let registeredURL = companiesURL.appendingPathComponent("registry-backed.sqlite")
        let legacyURL = companiesURL.appendingPathComponent("\(companyId.uuidString).sqlite")

        let registeredDB = try SQLiteDatabase(path: registeredURL.path)
        try MigrationRunner().runMigrations(on: registeredDB)
        _ = try TestCompany.seed(into: registeredDB, companyId: companyId, companyName: "Delete Path Co")
        registeredDB.close()

        let legacyDB = try SQLiteDatabase(path: legacyURL.path)
        try MigrationRunner().runMigrations(on: legacyDB)
        legacyDB.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Delete Path Co", sqliteFileName: registeredURL.lastPathComponent)
        )

        try await manager.deleteCompanyFiles(id: companyId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path + "-shm"))
        let deletedEntry = try await manager.findCompany(id: companyId)
        XCTAssertNil(deletedEntry)
    }

    func testDeleteCompanyFilesStillCleansSidecarsWhenPrimaryFileIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let companiesURL = root.appendingPathComponent("Companies", isDirectory: true)
        let registeredURL = companiesURL.appendingPathComponent("gone-primary.sqlite")
        let legacyURL = companiesURL.appendingPathComponent("\(companyId.uuidString).sqlite")

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Missing Primary Co", sqliteFileName: registeredURL.lastPathComponent)
        )

        let registeredWal = URL(fileURLWithPath: registeredURL.path + "-wal")
        let registeredShm = URL(fileURLWithPath: registeredURL.path + "-shm")
        try Data("wal".utf8).write(to: registeredWal)
        try Data("shm".utf8).write(to: registeredShm)

        try await manager.deleteCompanyFiles(id: companyId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredWal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registeredShm.path))
        let deletedEntry = try await manager.findCompany(id: companyId)
        XCTAssertNil(deletedEntry)
    }
}

private final class DatabaseOpenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }
}
