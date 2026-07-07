import XCTest
@testable import Avelo

final class LongOperationActivityTests: XCTestCase {

    private final class ActivityProbe: @unchecked Sendable, LongOperationActivityControlling {
        private let lock = NSLock()
        private(set) var reasons: [String] = []
        private(set) var beginCount = 0
        private(set) var endCount = 0

        func perform<T>(reason: String, operation: () throws -> T) throws -> T {
            begin(reason: reason)
            defer { end() }
            return try operation()
        }

        func perform<T>(reason: String, operation: () async throws -> T) async throws -> T {
            begin(reason: reason)
            defer { end() }
            return try await operation()
        }

        private func begin(reason: String) {
            lock.lock()
            reasons.append(reason)
            beginCount += 1
            lock.unlock()
        }

        private func end() {
            lock.lock()
            endCount += 1
            lock.unlock()
        }
    }

    private struct ThrowingMigration: Migration {
        let version: SchemaVersion = .v1
        let description: String = "throwing migration"

        func up(_ db: SQLiteDatabase) throws {
            throw AppError.unexpected("migration failed")
        }
    }

    func testMigrationRunnerReleasesActivityWhenMigrationThrows() throws {
        let probe = ActivityProbe()
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        XCTAssertThrowsError(
            try MigrationRunner(migrations: [ThrowingMigration()], activityController: probe).runMigrations(on: db)
        )
        XCTAssertEqual(probe.reasons, ["Avelo database migration"])
        XCTAssertEqual(probe.beginCount, 1)
        XCTAssertEqual(probe.endCount, 1)
    }

    func testBackupExportReleasesActivityWhenExportFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let company = try await CompanyService.create(
            companyInput: .init(name: "Backup Activity Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        let probe = ActivityProbe()

        let destinationURL = root
            .appendingPathComponent("missing-output-dir", isDirectory: true)
            .appendingPathComponent("activity.avelobackup")

        await XCTAssertThrowsErrorAsync(
            try await BackupService(manager: manager, activityController: probe).export(
                companyId: company.id,
                companyName: company.name,
                to: destinationURL
            )
        )
        XCTAssertEqual(probe.reasons, ["Avelo backup export"])
        XCTAssertEqual(probe.beginCount, 1)
        XCTAssertEqual(probe.endCount, 1)
    }

    func testRestoreReleasesActivityWhenRestoreFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let restoreRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restoreRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: restoreRoot)
        }

        let backupURL = root.appendingPathComponent("corrupt.avelobackup")
        try Data("not sqlite".utf8).write(to: backupURL)

        let manager = try DatabaseManager(appSupportDirectory: restoreRoot, keyStore: InMemoryCompanyKeyStore())
        let probe = ActivityProbe()

        await XCTAssertThrowsErrorAsync(
            try await RestoreService(manager: manager, activityController: probe).restore(from: backupURL)
        )
        XCTAssertEqual(probe.reasons, ["Avelo backup restore"])
        XCTAssertEqual(probe.beginCount, 1)
        XCTAssertEqual(probe.endCount, 1)
    }

    func testInventoryRecalculationReleasesActivityAfterRepublish() throws {
        let tc = try TestCompany.make()
        let probe = ActivityProbe()
        let service = InventoryService(db: tc.db, companyId: tc.companyId, activityController: probe)
        let item = try service.createItem(code: "ACT-ITEM", name: "Activity Item", unit: "NOS")

        try service.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            type: .stockIn,
            quantity: 5,
            ratePaise: 100
        )

        XCTAssertEqual(probe.reasons, ["Avelo inventory valuation recalculation"])
        XCTAssertEqual(probe.beginCount, 1)
        XCTAssertEqual(probe.endCount, 1)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message().isEmpty ? "Expected async throw" : message(), file: file, line: line)
    } catch {}
}
