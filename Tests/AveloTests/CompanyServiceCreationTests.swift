import XCTest
@testable import Avelo

final class CompanyServiceCreationTests: XCTestCase {

    func testCreateWithoutSeedDefaultsSkipsSeedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyStore = InMemoryCompanyKeyStore()
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: keyStore)

        let company = try await CompanyService.create(
            companyInput: .init(name: "No Seed Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: false,
            manager: manager
        )

        let fileURL = try await manager.companyFileURL(id: company.id)
        let key = try XCTUnwrap(try keyStore.retrieve(companyId: company.id))
        let db = try SQLiteDatabase(path: fileURL.path, key: key)
        defer { db.close() }

        let companyCount = try db.queryOne("SELECT COUNT(*) FROM avelo_companies") { $0.int(0) } ?? 0
        let financialYearCount = try db.queryOne("SELECT COUNT(*) FROM avelo_financial_years") { $0.int(0) } ?? 0
        let accountCount = try db.queryOne("SELECT COUNT(*) FROM avelo_accounts") { $0.int(0) } ?? 0
        let voucherTypeCount = try db.queryOne("SELECT COUNT(*) FROM avelo_voucher_types") { $0.int(0) } ?? 0

        XCTAssertEqual(companyCount, 1)
        XCTAssertEqual(financialYearCount, 1)
        XCTAssertEqual(accountCount, 0)
        XCTAssertEqual(voucherTypeCount, 0)
    }

    func testCreateRollsBackFileAndKeyWhenRegistryRegistrationFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyStore = InMemoryCompanyKeyStore()
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: keyStore)

        _ = try await CompanyService.create(
            companyInput: .init(name: "Collision Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )

        do {
            _ = try await CompanyService.create(
                companyInput: .init(name: "Collision Co", gstin: nil, pan: nil),
                fyInput: .init(
                    label: "2025-26",
                    startDate: DateFormatters.parseDate("2025-04-01")!,
                    endDate: DateFormatters.parseDate("2026-03-31")!,
                    booksBeginDate: DateFormatters.parseDate("2025-04-01")!
                ),
                seedDefaults: true,
                manager: manager
            )
            XCTFail("Expected duplicate company name registration to fail")
        } catch {
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected registry collision business rule, got \(error)")
            }
            XCTAssertTrue(message.contains("Collision Co"))
        }

        let registryPath = await manager.registryPath
        let registryDb = try SQLiteDatabase(path: registryPath)
        defer { registryDb.close() }
        let registeredCompanies = try RegistryRepository(db: registryDb).listCompanies()
        XCTAssertEqual(registeredCompanies.count, 1)
        XCTAssertEqual(registeredCompanies.first?.name, "Collision Co")

        let companiesDirectory = await manager.companiesDirectory
        let companyFiles = try FileManager.default.contentsOfDirectory(
            at: companiesDirectory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "sqlite" }
        XCTAssertEqual(companyFiles.count, 1)
        XCTAssertEqual(keyStore.storedKeyCount, 1)
    }

    func testCreateCompanyFileDeletesStoredKeyAndFileWhenDatabaseOpenFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyStore = InMemoryCompanyKeyStore()
        let manager = try DatabaseManager(
            appSupportDirectory: root,
            keyStore: keyStore,
            databaseOpener: { _, _ in
                throw AppError.database(.openFailed("forced createCompanyFile failure"))
            }
        )
        let companyId = UUID()

        do {
            _ = try await manager.createCompanyFile(companyId: companyId)
            XCTFail("Expected createCompanyFile to fail")
        } catch {
            guard case AppError.database(.openFailed(let message)) = AppError.wrap(error) else {
                return XCTFail("Expected openFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("forced createCompanyFile failure"))
        }

        let fileURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(try keyStore.retrieve(companyId: companyId))
        XCTAssertEqual(keyStore.storedKeyCount, 0)
    }
}
