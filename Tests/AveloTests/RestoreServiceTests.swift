import XCTest
@testable import Avelo

final class RestoreServiceTests: XCTestCase {

    private final class ThrowingFileManager: FileManager {
        override func removeItem(at URL: URL) throws {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func makeBackedUpCompany(
        root: URL,
        name: String = "Backup Source Co"
    ) async throws -> (manager: DatabaseManager, company: Company, backupURL: URL, recoveryKey: String) {
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let company = try await CompanyService.create(
            companyInput: .init(name: name, gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: manager
        )
        let backupURL = root.appendingPathComponent("\(UUID().uuidString).avelobackup")
        _ = try await BackupService(manager: manager).export(companyId: company.id, companyName: company.name, to: backupURL)
        return (manager, company, backupURL, try await manager.recoveryKey(for: company.id))
    }

    private func tempArtifacts(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.contains(".tmp") }
    }

    func testCorruptRestoreFailsWithoutRegisteringCompany() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backupURL = root.appendingPathComponent("corrupt.avelobackup")
        try Data("not sqlite".utf8).write(to: backupURL)

        let restoreRoot = root.appendingPathComponent("restore", isDirectory: true)
        let manager = try DatabaseManager(appSupportDirectory: restoreRoot, keyStore: InMemoryCompanyKeyStore())

        do {
            _ = try await RestoreService(manager: manager).restore(from: backupURL)
            XCTFail("Expected corrupt restore to fail")
        } catch {
            let entries = try await manager.listCompanies()
            XCTAssertTrue(entries.isEmpty)
            let companiesDirectory = await manager.companiesDirectory
            let restoredFiles = try FileManager.default.contentsOfDirectory(
                at: companiesDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "sqlite" }
            XCTAssertTrue(restoredFiles.isEmpty)
        }
    }

    func testRestoreRejectsManifestOriginalFileNameThatIsNotSQLiteBeforeRegisteringCompany() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceManager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let sourceCompany = try await CompanyService.create(
            companyInput: .init(name: "Manifest Mismatch Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: sourceManager
        )

        let backupURL = sourceRoot.appendingPathComponent("manifest-mismatch.avelobackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: "Manifest Mismatch Co",
            to: backupURL
        )
        let manifestURL = backupURL.appendingPathExtension("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        manifest.originalFileName = "other.avelobackup"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backupURL)
            XCTFail("Expected manifest mismatch to fail")
        } catch {
            let entries = try await targetManager.listCompanies()
            XCTAssertTrue(entries.isEmpty)
        }
    }

    func testRestoreRejectsUnsupportedManifestVersionBeforeOpeningBackup() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Manifest Version Co")
        let manifestURL = backedUp.backupURL.appendingPathExtension("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        manifest.manifestVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            XCTFail("Expected unsupported manifest version to fail")
        } catch {
            guard case AppError.database(.schemaMismatch(let message)) = AppError.wrap(error) else {
                return XCTFail("Expected schemaMismatch, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("manifest version"))
            let companies = try await targetManager.listCompanies()
            XCTAssertTrue(companies.isEmpty)
        }
    }

    func testRestoreChecksChecksumBeforeOpeningOrRegisteringBackup() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Checksum Co")
        let handle = try FileHandle(forWritingTo: backedUp.backupURL)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size - 1)
        try handle.write(contentsOf: Data([0x01]))
        try handle.close()

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            XCTFail("Expected checksum mismatch")
        } catch {
            XCTAssertEqual(AppError.wrap(error), .database(.checksumMismatch))
            let companies = try await targetManager.listCompanies()
            XCTAssertTrue(companies.isEmpty)
        }
    }

    func testRestoreCleanupSwallowsSecondaryDeleteFailures() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let fm = ThrowingFileManager()
        XCTAssertNoThrow(RestoreService.cleanupRestoredCompanyFile(at: temp, fileManager: fm))
    }

    func testPrepareRestoredCompanyDatabaseRemapsCompanyAndWritesAudit() throws {
        let tc = try TestCompany.make()
        let targetCompanyId = UUID()
        try AuditTestKeySupport.ensureKey(for: targetCompanyId)

        try RestoreService.prepareRestoredCompanyDatabase(
            db: tc.db,
            restoredCompanyId: targetCompanyId,
            restoredCompanyName: "Restored Co"
        )

        let company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(targetCompanyId))
        XCTAssertEqual(company.name, "Restored Co")
        XCTAssertNil(try CompanyRepository(db: tc.db).findById(tc.companyId))

        let fyCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_financial_years WHERE company_id = ?",
            bind: [.text(targetCompanyId.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(fyCount, 1)

        let accountCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_accounts WHERE company_id = ?",
            bind: [.text(targetCompanyId.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(accountCount, 7)

        let auditEvents = try AuditRepository(db: tc.db).list(filter: .init(companyId: targetCompanyId))
        XCTAssertEqual(auditEvents.count, 1)
        XCTAssertEqual(auditEvents.first?.action, .backupImported)
        XCTAssertEqual(auditEvents.first?.entityId, targetCompanyId.uuidString)
    }

    func testPrepareRestoredCompanyDatabasePreservesOriginalErrorWhenTriggerCleanupFails() throws {
        let tc = try TestCompany.make()
        let targetCompanyId = UUID()
        try AuditTestKeySupport.ensureKey(for: targetCompanyId)
        try tc.db.execute("DROP TABLE avelo_inventory_items")
        try tc.db.execute("DROP TABLE avelo_vouchers")

        do {
            try RestoreService.prepareRestoredCompanyDatabase(
                db: tc.db,
                restoredCompanyId: targetCompanyId,
                restoredCompanyName: "Broken Restore Co"
            )
            XCTFail("Expected prepare to fail")
        } catch {
            let message: String
            switch AppError.wrap(error) {
            case .database(.execFailed(let value)), .database(.prepareFailed(let value)):
                message = value
            default:
                return XCTFail("Expected original SQLite error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("avelo_vouchers"))
        }
    }

    func testBackupRestoreRoundTripPreservesCompanyData() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let manager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        _ = try await manager.createCompanyFile(companyId: companyId)
        let dbURL = sourceRoot.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")
        let key = try XCTUnwrap(try manager.keyStore.retrieve(companyId: companyId))
        let db = try SQLiteDatabase(path: dbURL.path, key: key)
        defer { db.close() }

        let source = try TestCompany.seed(into: db, companyId: companyId, companyName: "Roundtrip Co")
        let entry = CompanyRegistryEntry(id: companyId, name: "Roundtrip Co", sqliteFileName: "\(companyId.uuidString).sqlite")
        try await manager.registerCompany(entry)

        let posted = try VoucherService(db: db, companyId: source.companyId).post(
            draft: source.draft(on: "2024-06-01", lines: [
                source.line(source.cashId, 50000, .debit),
                source.line(source.salesId, 50000, .credit)
            ]),
            in: source.fy
        )

        let backupURL = sourceRoot.appendingPathComponent("roundtrip.avelobackup")
        _ = try await BackupService(manager: manager).export(
            companyId: source.companyId,
            companyName: "Roundtrip Co",
            to: backupURL
        )

        let restoreManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        let restored = try await RestoreService(manager: restoreManager).restore(
            from: backupURL,
            recoveryKey: RecoveryKeyCodec.encode(key)
        )
        let restoredHandle = try await restoreManager.openCompany(id: restored.id)
        defer { Task { await restoreManager.closeCompany(id: restored.id) } }

        let restoredCompany = try XCTUnwrap(CompanyRepository(db: restoredHandle.db).findById(restored.id))
        XCTAssertEqual(restoredCompany.name, "Roundtrip Co")

        let restoredFY = try XCTUnwrap(FinancialYearRepository(db: restoredHandle.db).findMostRecent(restored.id))
        XCTAssertEqual(restoredFY.label, source.fy.label)

        let restoredVouchers = try VoucherService(db: restoredHandle.db, companyId: restored.id)
            .list(filter: .init(companyId: restored.id))
        XCTAssertEqual(restoredVouchers.count, 1)
        XCTAssertEqual(restoredVouchers.first?.number, posted.voucher.number)
        XCTAssertEqual(restoredVouchers.first?.totalPaise, posted.voucher.totalPaise)

        let restoreAudit = try AuditRepository(db: restoredHandle.db).list(
            filter: .init(companyId: restored.id, action: .backupImported)
        )
        XCTAssertEqual(restoreAudit.count, 1)
    }

    func testRestoreRejectsBackupWithOverlappingFinancialYears() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Overlap Backup Co")
        let sourceEntries = try await backedUp.manager.listCompanies()
        let sourceEntry = try XCTUnwrap(sourceEntries.first)
        let sourceURL = await backedUp.manager.companiesDirectory.appendingPathComponent(sourceEntry.sqliteFileName)
        let sourceDb = try SQLiteDatabase(path: sourceURL.path, key: try RecoveryKeyCodec.decode(backedUp.recoveryKey))
        defer { sourceDb.close() }

        try sourceDb.execute("DROP TRIGGER IF EXISTS trg_avelo_fy_no_overlap")
        try sourceDb.execute("DROP TRIGGER IF EXISTS trg_avelo_fy_no_overlap_update")
        try sourceDb.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(UUID().uuidString),
                .text(backedUp.company.id.uuidString),
                .text("Corrupt Overlap"),
                .date(DateFormatters.parseDate("2024-10-01")!),
                .date(DateFormatters.parseDate("2025-09-30")!),
                .date(DateFormatters.parseDate("2024-10-01")!),
                .timestamp(Date())
            ]
        )

        _ = try await BackupService(manager: backedUp.manager).export(
            companyId: backedUp.company.id,
            companyName: backedUp.company.name,
            to: backedUp.backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            XCTFail("Expected overlapping financial years restore to fail")
        } catch {
            guard case AppError.database(.schemaMismatch(let message)) = AppError.wrap(error) else {
                return XCTFail("Expected schemaMismatch, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overlapping financial years"))
            let companies = try await targetManager.listCompanies()
            XCTAssertTrue(companies.isEmpty)
        }
    }

    func testRestoreReopenSoakPreservesCompanyDataAcrossRepeatedCycles() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let manager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        _ = try await manager.createCompanyFile(companyId: companyId)
        let dbURL = sourceRoot.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")
        let key = try XCTUnwrap(try manager.keyStore.retrieve(companyId: companyId))
        let db = try SQLiteDatabase(path: dbURL.path, key: key)
        defer { db.close() }

        let source = try TestCompany.seed(into: db, companyId: companyId, companyName: "Soak Restore Co")
        let entry = CompanyRegistryEntry(id: companyId, name: "Soak Restore Co", sqliteFileName: "\(companyId.uuidString).sqlite")
        try await manager.registerCompany(entry)

        _ = try VoucherService(db: db, companyId: source.companyId).post(
            draft: source.draft(on: "2024-06-01", lines: [
                source.line(source.cashId, 50000, .debit),
                source.line(source.salesId, 50000, .credit)
            ]),
            in: source.fy
        )

        let backupURL = sourceRoot.appendingPathComponent("soak-restore.avelobackup")
        _ = try await BackupService(manager: manager).export(
            companyId: source.companyId,
            companyName: "Soak Restore Co",
            to: backupURL
        )

        for index in 0..<20 {
            let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: targetRoot) }

            let restoreManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
            let restored = try await RestoreService(manager: restoreManager).restore(
                from: backupURL,
                recoveryKey: RecoveryKeyCodec.encode(key)
            )
            let restoredHandle = try await restoreManager.openCompany(id: restored.id)

            let restoredCompany = try XCTUnwrap(CompanyRepository(db: restoredHandle.db).findById(restored.id))
            XCTAssertEqual(restoredCompany.name, "Soak Restore Co", "Iteration \(index)")

            let restoredFY = try XCTUnwrap(FinancialYearRepository(db: restoredHandle.db).findMostRecent(restored.id))
            XCTAssertEqual(restoredFY.label, source.fy.label, "Iteration \(index)")

            let restoredVouchers = try VoucherService(db: restoredHandle.db, companyId: restored.id)
                .list(filter: .init(companyId: restored.id))
            XCTAssertEqual(restoredVouchers.count, 1, "Iteration \(index)")
            XCTAssertEqual(restoredVouchers.first?.totalPaise, 50000, "Iteration \(index)")

            let balanceSheet = try ReportService(db: restoredHandle.db, companyId: restored.id)
                .balanceSheet(asOfDate: source.fy.endDate, financialYearId: restored.id)
            XCTAssertEqual(balanceSheet.totalAssetsPaise, balanceSheet.totalLiabilitiesPaise + balanceSheet.totalEquityPaise, "Iteration \(index)")

            await restoreManager.closeCompany(id: restored.id)
        }
    }

    func testFreshKeychainRecoveryKeyRestoreSoakDoesNotLeakKeysOrCorruptFiles() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Fresh Keychain Soak Co")
        let originalSize = try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber

        for index in 0..<10 {
            let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: targetRoot) }

            let keyStore = InMemoryCompanyKeyStore()
            let restoreManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: keyStore)
            let restored = try await RestoreService(manager: restoreManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            let handle = try await restoreManager.openCompany(id: restored.id)
            let company = try XCTUnwrap(CompanyRepository(db: handle.db).findById(restored.id), "Iteration \(index)")
            XCTAssertEqual(company.name, "Fresh Keychain Soak Co")
            XCTAssertEqual(keyStore.storedKeyCount, 1, "Iteration \(index)")
            let restoredURL = try await restoreManager.companyFileURL(id: restored.id)
            let restoredSize = try FileManager.default.attributesOfItem(atPath: restoredURL.path)[.size] as? NSNumber
            XCTAssertNotNil(restoredSize)
            XCTAssertNotEqual(restoredSize?.int64Value, 0)
            await restoreManager.closeCompany(id: restored.id)
        }

        let finalSize = try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber
        XCTAssertEqual(finalSize, originalSize)
    }

    func testRepeatedBackupRestoreCyclesKeepBackupStableAndRestoresReadable() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Backup Restore Soak Co")
        var previousSize = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber)?.int64Value)
        for index in 0..<50 {
            _ = try await BackupService(manager: backedUp.manager).export(
                companyId: backedUp.company.id,
                companyName: backedUp.company.name,
                to: backedUp.backupURL
            )
            let size = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber)?.int64Value)
            XCTAssertEqual(size, previousSize, "Backup size drifted at cycle \(index)")
            previousSize = size

            let restoreManager = try DatabaseManager(
                appSupportDirectory: targetRoot.appendingPathComponent("restore-\(index)", isDirectory: true),
                keyStore: InMemoryCompanyKeyStore()
            )
            let restored = try await RestoreService(manager: restoreManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            let handle = try await restoreManager.openCompany(id: restored.id)
            XCTAssertNotNil(try CompanyRepository(db: handle.db).findById(restored.id), "Cycle \(index)")
            await restoreManager.closeCompany(id: restored.id)
        }
    }

    func testBackupStagingFailureCleansTemporaryArtifactsAndKeepsNoPartialManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backedUp = try await makeBackedUpCompany(root: root, name: "Backup Failure Cleanup Co")
        let blockedURL = root.appendingPathComponent("missing-parent", isDirectory: true)
            .appendingPathComponent("blocked.avelobackup")

        do {
            _ = try await BackupService(manager: backedUp.manager).export(
                companyId: backedUp.company.id,
                companyName: backedUp.company.name,
                to: blockedURL
            )
            XCTFail("Expected backup replace failure")
        } catch {
            guard case AppError.fileSystem = AppError.wrap(error) else {
                return XCTFail("Expected fileSystem error, got \(error)")
            }
            XCTAssertTrue(try tempArtifacts(in: root).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: blockedURL.appendingPathExtension("manifest.json").path))
        }
    }

    func testRestoreRejectsDuplicateCompanyNameClearly() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceManager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let sourceCompany = try await CompanyService.create(
            companyInput: .init(name: "Duplicate Restore Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: sourceManager
        )

        let backupURL = sourceRoot.appendingPathComponent("duplicate-restore.avelobackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: "Duplicate Restore Co",
            to: backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        _ = try await CompanyService.create(
            companyInput: .init(name: "Duplicate Restore Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: targetManager
        )

        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backupURL)
            XCTFail("Expected restore to reject duplicate company names")
        } catch {
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected businessRule error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("already exists"))
        }
    }

    func testRestoreFailsClearlyWhenDestinationCompanyFileCannotBeWritten() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            let companiesDir = targetRoot.appendingPathComponent("Companies", isDirectory: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: companiesDir.path)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceManager = try DatabaseManager(appSupportDirectory: sourceRoot, keyStore: InMemoryCompanyKeyStore())
        let sourceCompany = try await CompanyService.create(
            companyInput: .init(name: "Restore Permission Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: sourceManager
        )

        let backupURL = sourceRoot.appendingPathComponent("restore-permission.avelobackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: "Restore Permission Co",
            to: backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        let companiesDirectory = await targetManager.companiesDirectory
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: companiesDirectory.path
        )

        do {
            _ = try await RestoreService(manager: targetManager).restore(from: backupURL)
            XCTFail("Expected restore to fail when the destination company directory is not writable")
        } catch {
            guard case AppError.fileSystem(let message) = AppError.wrap(error) else {
                return XCTFail("Expected fileSystem error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("stage backup"))
        }
    }
}
