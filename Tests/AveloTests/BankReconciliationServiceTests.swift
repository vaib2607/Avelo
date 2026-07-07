import CryptoKit
import XCTest
@testable import Avelo

final class BankReconciliationServiceTests: XCTestCase {

    func testCSVParserReportsBadRowsAndKeepsValidRows() throws {
        let companyId = UUID()
        let accountId = UUID()
        let parsed = BankStatementCSVParser.parse(
            """
            date,amount,narration
            2024-06-03,-100.00,Vendor payment
            bad-date,10.00,Bad date
            2024-06-04,nope,Bad amount
            2024-06-05,25.00,
            """,
            companyId: companyId,
            accountId: accountId
        )

        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries.first?.companyId, companyId)
        XCTAssertEqual(parsed.entries.first?.accountId, accountId)
        XCTAssertEqual(parsed.entries.first?.amountPaise, -10_000)
        XCTAssertEqual(parsed.errors, [
            "Row 3: invalid date 'bad-date'.",
            "Row 4: invalid amount 'nope'.",
            "Row 5: narration is required."
        ])
    }

    func testCSVParserPreservesLargestNegativeInt64SafeAmount() {
        let companyId = UUID()
        let accountId = UUID()
        let parsed = BankStatementCSVParser.parse(
            """
            date,amount,narration
            2024-06-03,-92233720368547758.07,Extreme payment
            """,
            companyId: companyId,
            accountId: accountId
        )

        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries.first?.amountPaise, -Int64.max)
    }

    func testReconcileMatchesStatementLinesWithinDateTolerance() throws {
        let tc = try TestCompany.make()
        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(type: .payment, on: "2024-06-01", narration: "Rent paid", lines: [
                tc.line(tc.rentId, 10_000, .debit),
                tc.line(tc.cashId, 10_000, .credit)
            ]),
            in: tc.fy
        )
        let service = BankReconciliationService(db: tc.db, companyId: tc.companyId)
        try service.importStatement(accountId: tc.cashId, entries: [
            .init(
                id: UUID(),
                companyId: tc.companyId,
                accountId: tc.cashId,
                date: DateFormatters.parseDate("2024-06-03")!,
                amountPaise: -10_000,
                narration: "Cleared rent",
                isCleared: false
            )
        ])

        let exactOnly = try service.reconcile(
            accountId: tc.cashId,
            asOf: DateFormatters.parseDate("2024-06-30")!,
            dateToleranceDays: 0
        )
        XCTAssertEqual(exactOnly.matched.count, 0)
        XCTAssertEqual(exactOnly.unmatchedStatement.count, 1)

        let tolerant = try service.reconcile(
            accountId: tc.cashId,
            asOf: DateFormatters.parseDate("2024-06-30")!,
            dateToleranceDays: 3
        )
        XCTAssertEqual(tolerant.matched.count, 1)
        XCTAssertEqual(tolerant.matched.first?.voucherId, posted.voucher.id)
        XCTAssertEqual(tolerant.unmatchedStatement.count, 0)
        XCTAssertEqual(tolerant.bankBalancePaise, -10_000)
    }

    func testReconcileDoesNotTrapOnInt64MinStatementAmount() throws {
        let tc = try TestCompany.make()
        let service = BankReconciliationService(db: tc.db, companyId: tc.companyId)
        try service.importStatement(accountId: tc.cashId, entries: [
            .init(
                id: UUID(),
                companyId: tc.companyId,
                accountId: tc.cashId,
                date: DateFormatters.parseDate("2024-06-03")!,
                amountPaise: Int64.min,
                narration: "Extreme reversal",
                isCleared: false
            )
        ])

        let result = try service.reconcile(
            accountId: tc.cashId,
            asOf: DateFormatters.parseDate("2024-06-30")!,
            dateToleranceDays: 3
        )
        XCTAssertEqual(result.matched.count, 0)
        XCTAssertEqual(result.unmatchedStatement.count, 1)
        XCTAssertEqual(result.bankBalancePaise, Int64.min)
    }

    func testDateToleranceHelperDoesNotTrapOnIntMinDelta() {
        XCTAssertFalse(BankReconciliationService.isDeltaWithinTolerance(deltaDays: Int.min, allowedDays: 3))
        XCTAssertTrue(BankReconciliationService.isDeltaWithinTolerance(deltaDays: -3, allowedDays: 3))
        XCTAssertTrue(BankReconciliationService.isDeltaWithinTolerance(deltaDays: 3, allowedDays: 3))
        XCTAssertFalse(BankReconciliationService.isDeltaWithinTolerance(deltaDays: -4, allowedDays: 3))
    }

    func testClearStatementLineMarksImportedLineCleared() throws {
        let tc = try TestCompany.make()
        let repo = BankReconciliationRepository(db: tc.db)
        try repo.insertStatementLine(
            companyId: tc.companyId,
            accountId: tc.cashId,
            date: DateFormatters.parseDate("2024-06-03")!,
            amountPaise: -10_000,
            narration: "Cleared rent"
        )
        let line = try XCTUnwrap(repo.statementLines(accountId: tc.cashId, asOf: DateFormatters.parseDate("2024-06-30")!).first)

        try BankReconciliationService(db: tc.db, companyId: tc.companyId).clearStatementLine(id: line.id)

        let reloaded = try XCTUnwrap(repo.statementLines(accountId: tc.cashId, asOf: DateFormatters.parseDate("2024-06-30")!).first)
        XCTAssertTrue(reloaded.isCleared)
    }

    func testRestoringV3BackupMigratesAndBankingWorksAfterOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backupURL = root.appendingPathComponent("old-v3.sqlite")
        let oldDB = try SQLiteDatabase(path: backupURL.path)
        try MigrationRunner(migrations: [MigrationV001(), MigrationV002(), MigrationV003()]).runMigrations(on: oldDB)
        _ = try TestCompany.seed(into: oldDB, companyId: UUID(), companyName: "Old Backup Co")
        oldDB.close()
        try writeManifest(for: backupURL, companyName: "Old Backup Co", schemaVersion: 3)

        let manager = try DatabaseManager(appSupportDirectory: root.appendingPathComponent("App", isDirectory: true), keyStore: InMemoryCompanyKeyStore())
        let restored = try await RestoreService(manager: manager).restore(from: backupURL)
        let handle = try await manager.openCompany(id: restored.id)

        XCTAssertEqual(try handle.db.userVersion(), SchemaVersion.current.rawValue)
        try BankReconciliationRepository(db: handle.db).insertStatementLine(
            companyId: restored.id,
            accountId: try firstAccountId(in: handle.db, companyId: restored.id),
            date: DateFormatters.parseDate("2024-06-03")!,
            amountPaise: -1_000,
            narration: "Post-restore line"
        )
    }

    func testEncryptedV3CompanyMigratesAndBankingWorksAfterOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyStore = InMemoryCompanyKeyStore()
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: keyStore)
        let companyId = UUID()
        let key = try keyStore.generateKey()
        try keyStore.store(key: key, companyId: companyId)
        let fileURL = root.appendingPathComponent("Companies", isDirectory: true).appendingPathComponent("\(companyId.uuidString).sqlite")
        let oldDB = try SQLiteDatabase(path: fileURL.path, key: key)
        try MigrationRunner(migrations: [MigrationV001(), MigrationV002(), MigrationV003()]).runMigrations(on: oldDB)
        let seeded = try TestCompany.seed(into: oldDB, companyId: companyId, companyName: "Encrypted V3 Co")
        oldDB.close()
        try await manager.registerCompany(.init(id: companyId, name: "Encrypted V3 Co", sqliteFileName: fileURL.lastPathComponent))

        let handle = try await manager.openCompany(id: companyId)
        XCTAssertEqual(try handle.db.userVersion(), SchemaVersion.current.rawValue)
        try BankReconciliationRepository(db: handle.db).insertStatementLine(
            companyId: companyId,
            accountId: seeded.cashId,
            date: DateFormatters.parseDate("2024-06-03")!,
            amountPaise: -1_000,
            narration: "Encrypted migrated line"
        )
        XCTAssertEqual(try BankReconciliationRepository(db: handle.db).statementLines(accountId: seeded.cashId, asOf: DateFormatters.parseDate("2024-06-30")!).count, 1)
    }
}

private func firstAccountId(in db: SQLiteDatabase, companyId: Company.ID) throws -> Account.ID {
    try XCTUnwrap(
        db.queryOne(
            "SELECT id FROM avelo_accounts WHERE company_id = ? ORDER BY code LIMIT 1",
            bind: [.text(companyId.uuidString)]
        ) { try UUIDParsing.required($0.text("id"), field: "avelo_accounts.id") }
    )
}

private func writeManifest(for backupURL: URL, companyName: String, schemaVersion: Int) throws {
    let data = try Data(contentsOf: backupURL)
    let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let manifest = BackupManifest(
        manifestVersion: 1,
        schemaVersion: schemaVersion,
        companyName: companyName,
        exportedAt: Date(),
        checksumSHA256: checksum,
        originalFileName: backupURL.lastPathComponent,
        byteCount: Int64(data.count)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: backupURL.appendingPathExtension("manifest.json"), options: .atomic)
}
