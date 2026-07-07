import XCTest
@testable import Avelo

final class RegistryRepositoryTests: XCTestCase {

    private let createdAtA = Date(timeIntervalSince1970: 1_720_347_200)
    private let createdAtB = Date(timeIntervalSince1970: 1_720_350_800)
    private let openedAt = Date(timeIntervalSince1970: 1_720_354_400)

    func testRegisterRejectsDuplicateNameWithoutReplacingExistingRow() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        let repository = RegistryRepository(db: db)

        let original = CompanyRegistryEntry(
            id: UUID(),
            name: "Primary Co",
            sqliteFileName: "primary.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtA
        )
        try repository.register(original)

        let colliding = CompanyRegistryEntry(
            id: UUID(),
            name: "Primary Co",
            sqliteFileName: "other.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtB
        )

        XCTAssertThrowsError(try repository.register(colliding)) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected duplicate-name business rule, got \(error)")
            }
            XCTAssertTrue(message.contains("Primary Co"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("already registered"))
        }

        let rows = try repository.listCompanies()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, original.id)
        XCTAssertEqual(rows.first?.name, original.name)
        XCTAssertEqual(rows.first?.sqliteFileName, original.sqliteFileName)
    }

    func testRegisterRejectsDuplicateFileNameWithoutReplacingExistingRow() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        let repository = RegistryRepository(db: db)

        let original = CompanyRegistryEntry(
            id: UUID(),
            name: "Primary Co",
            sqliteFileName: "shared.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtA
        )
        try repository.register(original)

        let colliding = CompanyRegistryEntry(
            id: UUID(),
            name: "Other Co",
            sqliteFileName: "shared.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtB
        )

        XCTAssertThrowsError(try repository.register(colliding)) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected duplicate-file business rule, got \(error)")
            }
            XCTAssertTrue(message.contains("shared.sqlite"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("already registered"))
        }

        let rows = try repository.listCompanies()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, original.id)
        XCTAssertEqual(rows.first?.name, original.name)
        XCTAssertEqual(rows.first?.sqliteFileName, original.sqliteFileName)
    }

    func testRegisterUpdatesExistingRowByIdWithoutDeletingOthers() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(DatabaseManager.registrySchemaSQL)
        let repository = RegistryRepository(db: db)

        let original = CompanyRegistryEntry(
            id: UUID(),
            name: "Primary Co",
            sqliteFileName: "primary.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtA
        )
        let other = CompanyRegistryEntry(
            id: UUID(),
            name: "Other Co",
            sqliteFileName: "other.sqlite",
            lastOpenedAt: nil,
            createdAt: createdAtB
        )
        try repository.register(original)
        try repository.register(other)

        let updated = CompanyRegistryEntry(
            id: original.id,
            name: "Primary Co Renamed",
            sqliteFileName: "primary-renamed.sqlite",
            lastOpenedAt: openedAt,
            createdAt: original.createdAt
        )
        try repository.register(updated)

        let rows = try repository.listCompanies()
        XCTAssertEqual(rows.count, 2)

        let refreshedOriginal = try XCTUnwrap(repository.findById(original.id))
        XCTAssertEqual(refreshedOriginal.name, updated.name)
        XCTAssertEqual(refreshedOriginal.sqliteFileName, updated.sqliteFileName)
        XCTAssertEqual(refreshedOriginal.lastOpenedAt, updated.lastOpenedAt)
        XCTAssertEqual(refreshedOriginal.createdAt, updated.createdAt)

        let refreshedOther = try XCTUnwrap(repository.findById(other.id))
        XCTAssertEqual(refreshedOther.name, other.name)
        XCTAssertEqual(refreshedOther.sqliteFileName, other.sqliteFileName)
    }

    func testDatabaseManagerRegisterCompanyRejectsCollisionAndPreservesOriginalRow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let original = CompanyRegistryEntry(id: UUID(), name: "Managed Co", sqliteFileName: "managed.sqlite")
        try await manager.registerCompany(original)

        let colliding = CompanyRegistryEntry(id: UUID(), name: "Managed Co", sqliteFileName: "colliding.sqlite")
        do {
            try await manager.registerCompany(colliding)
            XCTFail("Expected duplicate company name rejection")
        } catch {
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule collision, got \(error)")
            }
            XCTAssertTrue(message.contains("Managed Co"))
        }

        let companies = try await manager.listCompanies()
        XCTAssertEqual(companies.count, 1)
        XCTAssertEqual(companies.first?.id, original.id)
        XCTAssertEqual(companies.first?.sqliteFileName, original.sqliteFileName)
    }
}
