import XCTest
@testable import Avelo

final class RestoreServiceTests: XCTestCase {

    private final class RestoreActivityProbe: @unchecked Sendable, LongOperationActivityControlling {
        private let lock = NSLock()
        private var _beginCount = 0

        var beginCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _beginCount
        }

        func perform<T>(reason: String, operation: () throws -> T) throws -> T {
            begin()
            return try operation()
        }

        func perform<T>(reason: String, operation: () async throws -> T) async throws -> T {
            begin()
            return try await operation()
        }

        private func begin() {
            lock.lock()
            _beginCount += 1
            lock.unlock()
        }
    }

    private func excludedFromBackup(_ url: URL) throws -> Bool {
        try XCTUnwrap(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup)
    }

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

    func testRestoreExcludesRestoredCompanyFileFromBackup() async throws {
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
            companyInput: .init(name: "Excluded Restore Co", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: sourceManager
        )

        let backupURL = sourceRoot.appendingPathComponent("excluded-restore.avelobackup")
        _ = try await BackupService(manager: sourceManager).export(
            companyId: sourceCompany.id,
            companyName: sourceCompany.name,
            to: backupURL
        )

        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: InMemoryCompanyKeyStore())
        let restored = try await RestoreService(manager: targetManager).restore(
            from: backupURL,
            recoveryKey: try sourceManager.recoveryKey(for: sourceCompany.id)
        )

        let restoredURL = try await targetManager.companyFileURL(id: restored.id)
        XCTAssertTrue(try excludedFromBackup(restoredURL))
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

    func testRestoreRejectsMistypedRecoveryKeyBeforeStartingOrMutatingDestination() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Typo Protection Source")
        let targetKeyStore = InMemoryCompanyKeyStore()
        let targetManager = try DatabaseManager(appSupportDirectory: targetRoot, keyStore: targetKeyStore)
        let preservedCompany = try await CompanyService.create(
            companyInput: .init(name: "Destination Stays Intact", gstin: nil, pan: nil),
            fyInput: .init(
                label: "2024-25",
                startDate: DateFormatters.parseDate("2024-04-01")!,
                endDate: DateFormatters.parseDate("2025-03-31")!,
                booksBeginDate: DateFormatters.parseDate("2024-04-01")!
            ),
            seedDefaults: true,
            manager: targetManager
        )
        let preservedURL = try await targetManager.companyFileURL(id: preservedCompany.id)
        let preservedBytes = try Data(contentsOf: preservedURL)
        let activity = RestoreActivityProbe()
        var mistypedRecoveryKey = backedUp.recoveryKey
        let payloadIndex = mistypedRecoveryKey.index(mistypedRecoveryKey.startIndex, offsetBy: 4)
        let originalCharacter = mistypedRecoveryKey[payloadIndex]
        let replacement = originalCharacter == "A" ? "B" : "A"
        mistypedRecoveryKey.replaceSubrange(payloadIndex...payloadIndex, with: replacement)

        do {
            _ = try await RestoreService(manager: targetManager, activityController: activity).restore(
                from: backedUp.backupURL,
                recoveryKey: mistypedRecoveryKey
            )
            XCTFail("Expected recovery-key checksum mismatch")
        } catch {
            XCTAssertEqual(AppError.wrap(error), .recoveryKey(.checksumMismatch))
        }

        XCTAssertEqual(activity.beginCount, 0)
        let companies = try await targetManager.listCompanies()
        XCTAssertEqual(companies.count, 1)
        XCTAssertEqual(companies.first?.id, preservedCompany.id)
        XCTAssertEqual(try Data(contentsOf: preservedURL), preservedBytes)
        XCTAssertEqual(targetKeyStore.storedKeyCount, 1)
        let companiesDirectory = await targetManager.companiesDirectory
        let stagedFiles = try FileManager.default.contentsOfDirectory(at: companiesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".restore-") }
        XCTAssertTrue(stagedFiles.isEmpty)
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

        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: tc.draft(
                on: "2024-06-01",
                lines: [
                    tc.line(tc.cashId, 1_000, .debit),
                    tc.line(tc.salesId, 1_000, .credit)
                ]
            ),
            in: tc.fy
        )
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(
            code: "RESTORE-ITEM",
            name: "Restore Item",
            unit: "NOS"
        )
        try VoucherItemLineRepository(db: tc.db).insertBatch([
            VoucherItemLine(
                companyId: tc.companyId,
                voucherId: posted.voucher.id,
                itemId: item.id,
                quantity: 1,
                ratePaise: 1_000,
                taxableValuePaise: 1_000
            )
        ])
        try VoucherDraftRepository(db: tc.db).upsert(
            VoucherEntryDraft(
                companyId: tc.companyId,
                voucherTypeCode: .journal,
                date: DateFormatters.parseDate("2024-06-02")!,
                narration: "Discard during restore",
                linesJSON: "[]"
            )
        )

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
        XCTAssertEqual(accountCount, 10)

        let restoredItemLines = try VoucherItemLineRepository(db: tc.db).findForVoucher(posted.voucher.id)
        XCTAssertEqual(restoredItemLines.count, 1)
        XCTAssertEqual(restoredItemLines.first?.companyId, targetCompanyId)
        XCTAssertNil(try VoucherDraftRepository(db: tc.db).mostRecent(companyId: targetCompanyId))

        let sourceRows = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_voucher_item_lines WHERE company_id = ?",
            bind: [.text(tc.companyId.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(sourceRows, 0)
        let remainingDrafts = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_voucher_drafts"
        ) { $0.int(0) }
        XCTAssertEqual(remainingDrafts, 0)

        let restoreAudit = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: targetCompanyId, action: .backupImported)
        )
        XCTAssertEqual(restoreAudit.count, 1)
        XCTAssertEqual(restoreAudit.first?.entityId, targetCompanyId.uuidString)
    }

    func testPrepareRestoredCompanyDatabasePreservesOriginalErrorWhenTriggerCleanupFails() throws {
        let tc = try TestCompany.make()
        let targetCompanyId = UUID()
        try AuditTestKeySupport.ensureKey(for: targetCompanyId)
        // With FK enforcement on (SQLiteDatabase's default), dropping
        // avelo_vouchers while avelo_voucher_item_lines' company-ownership
        // trigger still references the just-dropped avelo_inventory_items
        // makes SQLite reparse that trigger and fail with a misleading "no
        // such table: avelo_inventory_items" instead of ever reaching
        // avelo_vouchers. `RestoreService.prepareRestoredCompanyDatabase`
        // itself always disables FKs before touching schema (see its first
        // line) -- this setup step just matches that real precondition.
        try tc.db.execute("PRAGMA foreign_keys = OFF")
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

    func testHistoricalV14ThroughV22SchemasUpgradeAndRemapEveryCompanyScopedTable() throws {
        for version in 14...22 {
            let db = try SQLiteDatabase(path: ":memory:")
            let historicalMigrations = MigrationRunner.defaultMigrations.filter { $0.version.rawValue <= version }
            try MigrationRunner(migrations: historicalMigrations).runMigrations(on: db)

            let fixture = try seedHistoricalRestoreFixture(db: db, version: version)
            try MigrationRunner().runMigrations(on: db)
            XCTAssertEqual(try db.userVersion(), SchemaVersion.current.rawValue, "V\(version) did not upgrade")
            try PartyProfileRepository(db: db).upsert(PartyProfile(
                accountId: fixture.accountId,
                companyId: fixture.companyId,
                usage: .both,
                maintainBillwise: true
            ))

            let restoredCompanyId = UUID()
            try AuditTestKeySupport.ensureKey(for: restoredCompanyId)
            try RestoreService.prepareRestoredCompanyDatabase(
                db: db,
                restoredCompanyId: restoredCompanyId,
                restoredCompanyName: "Restored V\(version)"
            )

            let scopedTables = try companyScopedTables(in: db)
            XCTAssertFalse(scopedTables.isEmpty, "V\(version) produced no company-scoped tables")
            for table in scopedTables {
                let leaked = try db.queryOne(
                    "SELECT COUNT(*) FROM \(table) WHERE company_id = ?",
                    bind: [.text(fixture.companyId.uuidString)]
                ) { $0.int(0) } ?? 0
                XCTAssertEqual(leaked, 0, "V\(version) leaked source identity in \(table)")
            }
            XCTAssertNotNil(try CompanyRepository(db: db).findById(restoredCompanyId))
            XCTAssertEqual(try db.query("PRAGMA foreign_key_check") { _ in true }.count, 0, "V\(version)")
            XCTAssertNil(try VoucherDraftRepository(db: db).mostRecent(companyId: restoredCompanyId), "V\(version) scratch draft survived")
            XCTAssertEqual(
                try PartyProfileRepository(db: db).find(accountId: fixture.accountId, companyId: restoredCompanyId)?.usage,
                .both,
                "V\(version) party profile was not remapped"
            )

            if version >= 20 {
                let itemLineCompany = try db.queryOne(
                    "SELECT company_id FROM avelo_voucher_item_lines WHERE id = ?",
                    bind: [.text(fixture.itemLineId.uuidString)]
                ) { try UUIDParsing.required($0.requiredText("company_id"), field: "fixture.item_line.company_id") }
                XCTAssertEqual(itemLineCompany, restoredCompanyId, "V\(version) item line was not remapped")
            }
            let restoreEvents = try AuditRepository(db: db).list(
                filter: .init(companyId: restoredCompanyId, action: .backupImported)
            )
            XCTAssertEqual(restoreEvents.count, 1, "V\(version) restore audit count")
            db.close()
        }
    }

    private struct HistoricalRestoreFixture {
        let companyId: Company.ID
        let accountId: Account.ID
        let itemLineId: UUID
    }

    private func seedHistoricalRestoreFixture(db: SQLiteDatabase, version: Int) throws -> HistoricalRestoreFixture {
        let companyId = UUID()
        let financialYearId = UUID()
        let groupId = UUID()
        let accountId = UUID()
        let voucherId = UUID()
        let itemId = UUID()
        let componentItemId = UUID()
        let itemLineId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())

        try db.execute(
            "INSERT INTO avelo_companies (id, name, is_inventory_enabled, inventory_link_mode, created_at, updated_at) VALUES (?, ?, 1, 'manual', ?, ?)",
            [.text(companyId.uuidString), .text("Historical V\(version)"), .text(now), .text(now)]
        )
        try db.execute(
            "INSERT INTO avelo_financial_years (id, company_id, label, start_date, end_date, books_begin_date, created_at) VALUES (?, ?, '2024-25', '2024-04-01', '2025-03-31', '2024-04-01', ?)",
            [.text(financialYearId.uuidString), .text(companyId.uuidString), .text(now)]
        )
        try db.execute(
            "INSERT INTO avelo_account_groups (id, company_id, code, name, nature, created_at) VALUES (?, ?, 'RESTORE', 'Restore Group', 'assets', ?)",
            [.text(groupId.uuidString), .text(companyId.uuidString), .text(now)]
        )
        try db.execute(
            "INSERT INTO avelo_accounts (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side, created_at, updated_at) VALUES (?, ?, ?, 'RESTORE-A', 'Restore Account', 0, 'debit', ?, ?)",
            [.text(accountId.uuidString), .text(companyId.uuidString), .text(groupId.uuidString), .text(now), .text(now)]
        )
        try db.execute(
            "INSERT INTO avelo_vouchers (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id, narration, total_paise, created_at, updated_at) VALUES (?, ?, ?, 'journal', 'RESTORE-1', '2024-06-01', ?, 'Historical restore', 100, ?, ?)",
            [.text(voucherId.uuidString), .text(companyId.uuidString), .text(financialYearId.uuidString), .text(accountId.uuidString), .text(now), .text(now)]
        )
        try db.execute(
            "INSERT INTO avelo_ledger_lines (id, company_id, voucher_id, account_id, amount_paise, side, line_order) VALUES (?, ?, ?, ?, 100, 'debit', 0), (?, ?, ?, ?, 100, 'credit', 1)",
            [.text(UUID().uuidString), .text(companyId.uuidString), .text(voucherId.uuidString), .text(accountId.uuidString), .text(UUID().uuidString), .text(companyId.uuidString), .text(voucherId.uuidString), .text(accountId.uuidString)]
        )
        for (id, code) in [(itemId, "RESTORE-I"), (componentItemId, "RESTORE-C")] {
            try db.execute(
                "INSERT INTO avelo_inventory_items (id, company_id, code, name, unit, created_at) VALUES (?, ?, ?, ?, 'NOS', ?)",
                [.text(id.uuidString), .text(companyId.uuidString), .text(code), .text(code), .text(now)]
            )
        }
        try db.execute(
            "INSERT INTO avelo_stock_movements (id, company_id, item_id, voucher_id, date, movement_type, quantity, unit_cost_paise, total_value_paise, created_at) VALUES (?, ?, ?, ?, '2024-06-01', 'in', 1, 100, 100, ?)",
            [.text(UUID().uuidString), .text(companyId.uuidString), .text(itemId.uuidString), .text(voucherId.uuidString), .text(now)]
        )

        if version >= 14 {
            try db.execute(
                "INSERT INTO avelo_financial_year_opening_balances (financial_year_id, source_financial_year_id, account_id, opening_balance_paise, opening_balance_side, created_at) VALUES (?, ?, ?, 100, 'debit', ?)",
                [.text(financialYearId.uuidString), .text(financialYearId.uuidString), .text(accountId.uuidString), .text(now)]
            )
        }
        if version >= 15 {
            try db.execute(
                "INSERT INTO avelo_bill_allocations (id, company_id, voucher_id, party_account_id, kind, reference_number, allocated_paise, created_at) VALUES (?, ?, ?, ?, 'New Ref', 'RESTORE-BILL', 100, ?)",
                [.text(UUID().uuidString), .text(companyId.uuidString), .text(voucherId.uuidString), .text(accountId.uuidString), .text(now)]
            )
        }
        if version >= 16 {
            try db.execute(
                "INSERT INTO avelo_cheques (id, company_id, voucher_id, cheque_number, issue_date, status, created_at) VALUES (?, ?, ?, 'RESTORE-CHQ', '2024-06-01', 'issued', ?)",
                [.text(UUID().uuidString), .text(companyId.uuidString), .text(voucherId.uuidString), .text(now)]
            )
        }
        if version >= 17 {
            let bomId = UUID()
            try db.execute(
                "INSERT INTO avelo_boms (id, company_id, assembly_item_id, output_quantity, created_at, updated_at) VALUES (?, ?, ?, 1.0, ?, ?)",
                [.text(bomId.uuidString), .text(companyId.uuidString), .text(itemId.uuidString), .text(now), .text(now)]
            )
            try db.execute(
                "INSERT INTO avelo_bom_components (id, company_id, bom_id, component_item_id, quantity, line_order) VALUES (?, ?, ?, ?, 1.0, 0)",
                [.text(UUID().uuidString), .text(companyId.uuidString), .text(bomId.uuidString), .text(componentItemId.uuidString)]
            )
        }
        if version >= 18 {
            try db.execute(
                "INSERT INTO avelo_voucher_drafts (id, company_id, voucher_type_code, date, narration, lines_json, updated_at) VALUES (?, ?, 'journal', '2024-06-01', 'discard me', '[]', ?)",
                [.text(UUID().uuidString), .text(companyId.uuidString), .text(now)]
            )
        }
        if version >= 20 {
            try db.execute(
                "INSERT INTO avelo_voucher_item_lines (id, company_id, voucher_id, item_id, quantity, rate_paise, taxable_value_paise, created_at) VALUES (?, ?, ?, ?, 1, 100, 100, ?)",
                [.text(itemLineId.uuidString), .text(companyId.uuidString), .text(voucherId.uuidString), .text(itemId.uuidString), .text(now)]
            )
        }
        return HistoricalRestoreFixture(companyId: companyId, accountId: accountId, itemLineId: itemLineId)
    }

    private func companyScopedTables(in db: SQLiteDatabase) throws -> [String] {
        let tables = try db.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'avelo_%' ORDER BY name"
        ) { try $0.requiredText("name") }
        return try tables.filter { table in
            try db.query("PRAGMA table_info(\(table))") { $0.text("name") }.contains("company_id")
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
        let inventory = InventoryService(db: db, companyId: source.companyId)
        let bomService = BOMService(db: db, companyId: source.companyId)
        let assembly = try inventory.createItem(code: "FG-REST", name: "Restored FG", unit: "PCS")
        let component = try inventory.createItem(code: "RM-REST", name: "Restored RM", unit: "PCS")
        try bomService.createBOM(
            assemblyItemId: assembly.id,
            outputQuantity: try ExactQuantity.parse(decimal: "1"),
            components: [
                BOMComponent(
                    companyId: source.companyId,
                    bomId: UUID(),
                    componentItemId: component.id,
                    quantity: try ExactQuantity.parse(decimal: "2")
                )
            ]
        )
        let posted = try VoucherService(db: db, companyId: source.companyId).post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .payment,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Roundtrip cheque payment",
                lines: [
                    .init(accountId: source.rentId, amountPaise: 50000, side: .debit),
                    .init(accountId: source.cashId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: source.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "REST-CHQ-001",
                chequeDueDate: DateFormatters.parseDate("2024-06-15")!,
                chequeStatus: .deposited
            )
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
        let restoredWorkflow = try AccountingWorkflowsRepository(db: restoredHandle.db).workflowInputs(for: try XCTUnwrap(restoredVouchers.first?.id))
        XCTAssertEqual(restoredWorkflow.chequeNumber, "REST-CHQ-001")
        XCTAssertEqual(restoredWorkflow.chequeStatus, .deposited)
        let restoredBom = try XCTUnwrap(BOMService(db: restoredHandle.db, companyId: restored.id).loadBOM(for: assembly.id))
        XCTAssertEqual(restoredBom.0.assemblyItemId, assembly.id)
        XCTAssertEqual(restoredBom.0.outputQuantity, try ExactQuantity.parse(decimal: "1"))
        XCTAssertEqual(restoredBom.1.count, 1)
        XCTAssertEqual(restoredBom.1[0].componentItemId, component.id)
        XCTAssertEqual(restoredBom.1[0].quantity, try ExactQuantity.parse(decimal: "2"))

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

    func testRepeatedBackupRestoreCyclesRemainBoundedAuditedAndReadable() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let backedUp = try await makeBackedUpCompany(root: sourceRoot, name: "Backup Restore Soak Co")
        let initialSize = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber)?.int64Value)
        var largestSize = initialSize
        for index in 0..<50 {
            _ = try await BackupService(manager: backedUp.manager).export(
                companyId: backedUp.company.id,
                companyName: backedUp.company.name,
                to: backedUp.backupURL
            )
            let size = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: backedUp.backupURL.path)[.size] as? NSNumber)?.int64Value)
            largestSize = max(largestSize, size)
            XCTAssertLessThanOrEqual(
                size,
                initialSize + 512 * 1_024,
                "Audit-backed backup growth exceeded the bounded soak allowance at cycle \(index)"
            )

            let restoreManager = try DatabaseManager(
                appSupportDirectory: targetRoot.appendingPathComponent("restore-\(index)", isDirectory: true),
                keyStore: InMemoryCompanyKeyStore()
            )
            let restored = try await RestoreService(manager: restoreManager).restore(from: backedUp.backupURL, recoveryKey: backedUp.recoveryKey)
            let handle = try await restoreManager.openCompany(id: restored.id)
            XCTAssertNotNil(try CompanyRepository(db: handle.db).findById(restored.id), "Cycle \(index)")
            await restoreManager.closeCompany(id: restored.id)
        }
        XCTAssertGreaterThanOrEqual(largestSize, initialSize)
        let sourceHandle = try await backedUp.manager.openCompany(id: backedUp.company.id)
        let exportEvents = try AuditRepository(db: sourceHandle.db).list(
            filter: .init(companyId: backedUp.company.id, action: .backupExported)
        )
        XCTAssertEqual(exportEvents.count, 51, "Initial backup plus 50 soak exports must each emit one event")
        await backedUp.manager.closeCompany(id: backedUp.company.id)
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

    func testBackupAuditFailureRemovesPublishedBackupAndManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backedUp = try await makeBackedUpCompany(root: root, name: "Backup Audit Rollback Co")
        let handle = try await backedUp.manager.openCompany(id: backedUp.company.id)
        try handle.db.execute(
            "CREATE TRIGGER test_reject_backup_export_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'backupExported' BEGIN SELECT RAISE(ABORT, 'test audit failure'); END;"
        )
        let rejectedURL = root.appendingPathComponent("rejected.avelobackup")

        do {
            _ = try await BackupService(manager: backedUp.manager).export(
                companyId: backedUp.company.id,
                companyName: backedUp.company.name,
                to: rejectedURL
            )
            XCTFail("Expected the audit failure to reject the backup")
        } catch {
            // Expected: publishing and audit are one externally visible operation.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedURL.appendingPathExtension("manifest.json").path))
        XCTAssertEqual(
            try AuditRepository(db: handle.db).list(filter: .init(companyId: backedUp.company.id, action: .backupExported)).count,
            1,
            "Only the successful setup export should remain audited"
        )
        await backedUp.manager.closeCompany(id: backedUp.company.id)
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
