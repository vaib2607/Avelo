import XCTest
@testable import Mally

final class DatabaseManagerFileResolutionTests: XCTestCase {

    func testOpenCompanyUsesRegistrySQLiteFileNameWhenItDiffersFromLegacyPattern() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
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

        let manager = try DatabaseManager(appSupportDirectory: root)
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

        let manager = try DatabaseManager(appSupportDirectory: root)
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

    func testBackupExportUsesRegisteredSQLiteFileName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
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

        let destinationURL = root.appendingPathComponent("backup-output.mallybackup")
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

        let manager = try DatabaseManager(appSupportDirectory: root)
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
            .appendingPathComponent("backup-output.mallybackup")

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
            XCTAssertTrue(message.localizedCaseInsensitiveContains("write backup file"))
        }
    }

    func testDeleteCompanyFilesRemovesRegisteredAndLegacyFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
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
    }
}
