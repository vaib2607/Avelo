import XCTest
@testable import Avelo

final class LegacyKeyMigrationServiceTests: XCTestCase {
    func testMigratesPlaintextDatabaseToPerCompanyKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let companyId = UUID()
        let url = root.appendingPathComponent("plain.sqlite")
        let plain = try SQLiteDatabase(path: url.path)
        try MigrationRunner().runMigrations(on: plain)
        _ = try TestCompany.seed(into: plain, companyId: companyId)
        plain.close()

        let store = InMemoryCompanyKeyStore()
        let key = try LegacyKeyMigrationService(keyStore: store).migrateIfNeeded(companyId: companyId, fileURL: url)
        XCTAssertEqual(try store.retrieve(companyId: companyId), key)

        XCTAssertThrowsError(try SQLiteDatabase(path: url.path))
        let encrypted = try SQLiteDatabase(path: url.path, key: key)
        defer { encrypted.close() }
        let count = try encrypted.queryOne("SELECT COUNT(*) FROM avelo_companies") { $0.int(0) } ?? 0
        XCTAssertEqual(count, 1)
    }

    func testMigratesOldHardcodedPassphraseDatabaseToPerCompanyKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let companyId = UUID()
        let url = root.appendingPathComponent("legacy.sqlite")
        let legacy = try SQLiteDatabase(path: url.path, encryptionKey: .passphrase(SQLiteDatabase.legacyHardcodedPassphrase))
        try MigrationRunner().runMigrations(on: legacy)
        _ = try TestCompany.seed(into: legacy, companyId: companyId)
        legacy.close()

        let store = InMemoryCompanyKeyStore()
        let key = try LegacyKeyMigrationService(keyStore: store).migrateIfNeeded(companyId: companyId, fileURL: url)
        XCTAssertEqual(try store.retrieve(companyId: companyId), key)

        XCTAssertThrowsError(try SQLiteDatabase(path: url.path, encryptionKey: .passphrase(SQLiteDatabase.legacyHardcodedPassphrase)))
        let encrypted = try SQLiteDatabase(path: url.path, key: key)
        defer { encrypted.close() }
        let count = try encrypted.queryOne("SELECT COUNT(*) FROM avelo_companies") { $0.int(0) } ?? 0
        XCTAssertEqual(count, 1)
    }
}
