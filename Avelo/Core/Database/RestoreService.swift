import Foundation
import CryptoKit
import os

private let AveloRestoreLogger = Logger(subsystem: "com.avelo.desktop", category: "restore")

public struct RestoreService: Sendable {

    public let manager: DatabaseManager
    private static let companyScopedTables: [String] = [
        "avelo_financial_years",
        "avelo_account_groups",
        "avelo_accounts",
        "avelo_voucher_types",
        "avelo_vouchers",
        "avelo_ledger_lines",
        "avelo_inventory_items",
        "avelo_inventory_order_lines",
        "avelo_inventory_orders",
        "avelo_inventory_reorder_levels",
        "avelo_stock_movements",
        "avelo_payroll_employees",
        "avelo_payroll_entries",
        "avelo_audit_events",
        "avelo_voucher_sequences",
        "avelo_voucher_templates",
        "avelo_bank_reconciliations",
        "avelo_bank_statement_lines"
    ]
    private static let auditImmutabilityTriggerSQL: [String] = [
        """
        CREATE TRIGGER trg_avelo_audit_no_update
        BEFORE UPDATE ON avelo_audit_events
        BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
        """,
        """
        CREATE TRIGGER trg_avelo_audit_no_delete
        BEFORE DELETE ON avelo_audit_events
        BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
        """
    ]
    private static let lockedFinancialYearTriggerNames: [String] = [
        "trg_avelo_voucher_fy_locked_insert",
        "trg_avelo_voucher_fy_locked_update",
        "trg_avelo_voucher_fy_locked_delete",
        "trg_avelo_voucher_date_in_fy_update",
        "trg_avelo_lines_fy_locked_insert",
        "trg_avelo_lines_fy_locked_update",
        "trg_avelo_lines_fy_locked_delete",
        "trg_avelo_stock_movements_fy_locked_insert",
        "trg_avelo_stock_movements_fy_locked_update",
        "trg_avelo_stock_movements_fy_locked_delete",
        "trg_avelo_payroll_entries_fy_locked_insert",
        "trg_avelo_payroll_entries_fy_locked_update",
        "trg_avelo_payroll_entries_fy_locked_delete",
        "trg_avelo_bank_statement_lines_fy_locked_insert",
        "trg_avelo_bank_statement_lines_fy_locked_update",
        "trg_avelo_bank_statement_lines_fy_locked_delete",
        "trg_avelo_bank_reconciliations_fy_locked_insert",
        "trg_avelo_bank_reconciliations_fy_locked_update",
        "trg_avelo_bank_reconciliations_fy_locked_delete",
        "trg_avelo_accounts_locked_opening_insert",
        "trg_avelo_accounts_locked_opening_update"
    ]
    private static let lockedFinancialYearTriggerSQL: [String] = [
        """
        CREATE TRIGGER trg_avelo_voucher_fy_locked_insert
        BEFORE INSERT ON avelo_vouchers
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = NEW.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; new vouchers are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_voucher_fy_locked_update
        BEFORE UPDATE ON avelo_vouchers
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
          OR (SELECT is_locked FROM avelo_financial_years WHERE id = NEW.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; voucher edits are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_voucher_date_in_fy_update
        BEFORE UPDATE ON avelo_vouchers
        FOR EACH ROW
        BEGIN
            SELECT RAISE(ABORT, 'Voucher date is outside its financial year')
            WHERE NOT EXISTS (
                SELECT 1 FROM avelo_financial_years fy
                WHERE fy.id = NEW.financial_year_id
                  AND fy.company_id = NEW.company_id
                  AND NEW.date BETWEEN fy.start_date AND fy.end_date
            );
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_voucher_fy_locked_delete
        BEFORE DELETE ON avelo_vouchers
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; voucher deletes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_lines_fy_locked_insert
        BEFORE INSERT ON avelo_ledger_lines
        WHEN NEW.voucher_id IN (
            SELECT id FROM avelo_vouchers
            WHERE financial_year_id IN (SELECT id FROM avelo_financial_years WHERE is_locked = 1)
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_lines_fy_locked_update
        BEFORE UPDATE ON avelo_ledger_lines
        WHEN OLD.voucher_id IN (
            SELECT id FROM avelo_vouchers
            WHERE financial_year_id IN (SELECT id FROM avelo_financial_years WHERE is_locked = 1)
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_lines_fy_locked_delete
        BEFORE DELETE ON avelo_ledger_lines
        WHEN OLD.voucher_id IN (
            SELECT id FROM avelo_vouchers
            WHERE financial_year_id IN (SELECT id FROM avelo_financial_years WHERE is_locked = 1)
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_stock_movements_fy_locked_insert
        BEFORE INSERT ON avelo_stock_movements
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; stock movements are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_stock_movements_fy_locked_update
        BEFORE UPDATE ON avelo_stock_movements
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.date BETWEEN fy.start_date AND fy.end_date
        ) OR EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; stock movement edits are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_stock_movements_fy_locked_delete
        BEFORE DELETE ON avelo_stock_movements
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; stock movement deletes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_payroll_entries_fy_locked_insert
        BEFORE INSERT ON avelo_payroll_entries
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = NEW.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; payroll entries are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_payroll_entries_fy_locked_update
        BEFORE UPDATE ON avelo_payroll_entries
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
          OR (SELECT is_locked FROM avelo_financial_years WHERE id = NEW.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; payroll entry edits are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_payroll_entries_fy_locked_delete
        BEFORE DELETE ON avelo_payroll_entries
        WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; payroll entry deletes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_statement_lines_fy_locked_insert
        BEFORE INSERT ON avelo_bank_statement_lines
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank statement changes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_statement_lines_fy_locked_update
        BEFORE UPDATE ON avelo_bank_statement_lines
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.statement_date BETWEEN fy.start_date AND fy.end_date
        ) OR EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank statement edits are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_statement_lines_fy_locked_delete
        BEFORE DELETE ON avelo_bank_statement_lines
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank statement deletes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_reconciliations_fy_locked_insert
        BEFORE INSERT ON avelo_bank_reconciliations
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank reconciliation changes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_reconciliations_fy_locked_update
        BEFORE UPDATE ON avelo_bank_reconciliations
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.statement_date BETWEEN fy.start_date AND fy.end_date
        ) OR EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
              AND NEW.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank reconciliation edits are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_bank_reconciliations_fy_locked_delete
        BEFORE DELETE ON avelo_bank_reconciliations
        WHEN EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = OLD.company_id
              AND fy.is_locked = 1
              AND OLD.statement_date BETWEEN fy.start_date AND fy.end_date
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; bank reconciliation deletes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_accounts_locked_opening_insert
        BEFORE INSERT ON avelo_accounts
        WHEN NEW.opening_balance_paise <> 0
          AND EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; opening balance changes are not allowed');
        END;
        """,
        """
        CREATE TRIGGER trg_avelo_accounts_locked_opening_update
        BEFORE UPDATE ON avelo_accounts
        WHEN (NEW.opening_balance_paise <> OLD.opening_balance_paise
              OR NEW.opening_balance_side <> OLD.opening_balance_side)
          AND EXISTS (
            SELECT 1 FROM avelo_financial_years fy
            WHERE fy.company_id = NEW.company_id
              AND fy.is_locked = 1
        )
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; opening balance changes are not allowed');
        END;
        """
    ]

    static var lockedFinancialYearTriggerNamesForMigration: [String] { lockedFinancialYearTriggerNames }
    static var lockedFinancialYearTriggerSQLForMigration: [String] { lockedFinancialYearTriggerSQL }

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func restore(from sourceURL: URL, recoveryKey: String? = nil) async throws -> CompanyRegistryEntry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            AveloRestoreLogger.error("restore source missing: \(sourceURL.path, privacy: .public)")
            throw AppError.notFound("Backup file not found")
        }

        let manifestURL: URL = {
            if sourceURL.pathExtension == "manifest.json" {
                return sourceURL
            }
            return sourceURL.appendingPathExtension("manifest.json")
        }()

        let manifest = try Self.loadManifest(
            manifestURL: manifestURL,
            sourceURL: sourceURL,
            fileManager: fm
        )
        try Self.validateManifest(manifest, sourceURL: sourceURL)

        let data = try Data(contentsOf: sourceURL)
        try Self.validateBackupData(data, manifest: manifest, sourceURL: sourceURL)

        let registryEntries = try await manager.listCompanies()
        if registryEntries.contains(where: { $0.name.caseInsensitiveCompare(manifest.companyName) == .orderedSame }) {
            AveloRestoreLogger.error("duplicate restore name rejected: \(manifest.companyName, privacy: .public)")
            throw AppError.businessRule("A company named \"\(manifest.companyName)\" already exists. Rename or remove the existing company before restoring this backup.")
        }

        let newId = UUID()
        let destURL = manager.companiesDirectory.appendingPathComponent("\(newId.uuidString).sqlite")
        let stagingURL = manager.companiesDirectory.appendingPathComponent(".restore-\(newId.uuidString).sqlite")
        Self.cleanupRestoredCompanyFile(at: stagingURL, fileManager: fm)
        defer { Self.cleanupRestoredCompanyFile(at: stagingURL, fileManager: fm) }
        if fm.fileExists(atPath: destURL.path) {
            do {
                try fm.removeItem(at: destURL)
            } catch {
                throw AppError.fileSystem("Unable to replace existing restored company file at \(destURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            try fm.copyItem(at: sourceURL, to: stagingURL)
        } catch {
            AveloRestoreLogger.error("restore staging copy failed to \(stagingURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to stage backup for restore at \(stagingURL.lastPathComponent): \(error.localizedDescription)")
        }

        do {
            let decodedRecoveryKey = try recoveryKey.map { try RecoveryKeyCodec.decode($0) }
            let opened = try Self.openStagedDatabase(stagingURL: stagingURL, key: decodedRecoveryKey)
            let db = opened.db
            defer { db.close() }
            try Self.validateIntegrity(db: db)
            let current = db.userVersion()
            guard current <= SchemaVersion.current.rawValue else {
                throw AppError.database(.schemaMismatch("Backup schema version \(current) is newer than this app supports."))
            }
            if current < SchemaVersion.current.rawValue {
                try MigrationRunner().runMigrations(on: db)
                try Self.validateIntegrity(db: db)
            }
            try Self.prepareRestoredCompanyDatabase(
                db: db,
                restoredCompanyId: newId,
                restoredCompanyName: manifest.companyName
            )
            try Self.validateIntegrity(db: db)
            try Self.validatePreparedCompany(db: db, companyId: newId, companyName: manifest.companyName)

            let storedKey: Data
            switch opened.source {
            case .keyed(let key):
                storedKey = key
            case .plaintext:
                storedKey = try manager.keyStore.generateKey()
                db.close()
                try LegacyKeyMigrationService(keyStore: manager.keyStore).migrate(
                    companyId: newId,
                    fileURL: stagingURL,
                    source: .plaintext,
                    newKey: storedKey
                )
            case .legacyPassphrase:
                storedKey = try manager.keyStore.generateKey()
                db.close()
                try LegacyKeyMigrationService(keyStore: manager.keyStore).migrate(
                    companyId: newId,
                    fileURL: stagingURL,
                    source: .hardcodedPassphrase,
                    newKey: storedKey
                )
            }

            let entry = CompanyRegistryEntry(
                id: newId,
                name: manifest.companyName,
                sqliteFileName: destURL.lastPathComponent,
                lastOpenedAt: nil,
                createdAt: Date()
            )
            db.close()
            try fm.moveItem(at: stagingURL, to: destURL)
            try manager.keyStore.store(key: storedKey, companyId: newId)
            try await manager.registerCompany(entry)
            return entry
        } catch {
            AveloRestoreLogger.error("restore failed, cleaning up \(stagingURL.path, privacy: .public)")
            Self.cleanupRestoredCompanyFile(at: destURL, fileManager: fm)
            Self.cleanupRestoredCompanyFile(at: stagingURL, fileManager: fm)
            throw error
        }
    }

    private enum StagedSource {
        case keyed(Data)
        case plaintext
        case legacyPassphrase
    }

    private static func openStagedDatabase(stagingURL: URL, key: Data?) throws -> (db: SQLiteDatabase, source: StagedSource) {
        if let key {
            return (try SQLiteDatabase(path: stagingURL.path, key: key), .keyed(key))
        }
        do {
            return (try SQLiteDatabase(path: stagingURL.path), .plaintext)
        } catch {
            do {
                return (
                    try SQLiteDatabase(path: stagingURL.path, encryptionKey: .passphrase(SQLiteDatabase.legacyHardcodedPassphrase)),
                    .legacyPassphrase
                )
            } catch {
                throw AppError.database(.missingEncryptionKey("This encrypted backup requires the company recovery key before it can be restored."))
            }
        }
    }

    private static func loadManifest(
        manifestURL: URL,
        sourceURL: URL,
        fileManager: FileManager
    ) throws -> BackupManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return BackupManifest(
                schemaVersion: SchemaVersion.current.rawValue,
                companyName: sourceURL.deletingPathExtension().lastPathComponent,
                exportedAt: Date(),
                checksumSHA256: "",
                originalFileName: sourceURL.lastPathComponent
            )
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode(BackupManifest.self, from: data)
        } catch {
            throw AppError.database(.schemaMismatch("Backup manifest could not be read or decoded."))
        }
    }

    private static func validateManifest(_ manifest: BackupManifest, sourceURL: URL) throws {
        guard manifest.manifestVersion == 1 else {
            throw AppError.database(.schemaMismatch("Unsupported backup manifest version \(manifest.manifestVersion)."))
        }
        guard manifest.schemaVersion > 0, manifest.schemaVersion <= SchemaVersion.current.rawValue else {
            throw AppError.database(.schemaMismatch("Unsupported backup schema version \(manifest.schemaVersion)."))
        }
        guard !manifest.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.database(.schemaMismatch("Backup manifest is missing the company name."))
        }
        if !manifest.originalFileName.isEmpty && URL(fileURLWithPath: manifest.originalFileName).pathExtension != "sqlite" {
            throw AppError.database(.schemaMismatch("Backup manifest original file name must identify a SQLite company file."))
        }
    }

    private static func validateBackupData(_ data: Data, manifest: BackupManifest, sourceURL: URL) throws {
        if manifest.byteCount > 0, manifest.byteCount != Int64(data.count) {
            throw AppError.database(.schemaMismatch("Backup file size does not match its manifest."))
        }
        if !manifest.checksumSHA256.isEmpty {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if hex != manifest.checksumSHA256 {
                AveloRestoreLogger.error("restore checksum mismatch for \(sourceURL.lastPathComponent, privacy: .public)")
                throw AppError.database(.checksumMismatch)
            }
        }
    }

    static func prepareRestoredCompanyDatabase(
        db: SQLiteDatabase,
        restoredCompanyId: Company.ID,
        restoredCompanyName: String
    ) throws {
        let sourceCompanies = try CompanyRepository(db: db).listForRegistry()
        guard sourceCompanies.count == 1, let sourceCompany = sourceCompanies.first else {
            AveloRestoreLogger.error("restore schema mismatch: unexpected company count \(sourceCompanies.count, privacy: .public)")
            throw AppError.database(.schemaMismatch("Restore expects exactly one company per backup file."))
        }
        if sourceCompany.id == restoredCompanyId {
            try writeRestoreAuditEvent(db: db, companyId: restoredCompanyId)
            return
        }

        try db.execute("PRAGMA foreign_keys = OFF")
        do {
            try dropAuditImmutabilityTriggers(db: db)
            try dropLockedFinancialYearTriggers(db: db)
            try db.write { tx in
                try tx.execute(
                    "UPDATE avelo_companies SET id = ?, name = ?, updated_at = ? WHERE id = ?",
                    [
                        .text(restoredCompanyId.uuidString),
                        .text(restoredCompanyName),
                        .timestamp(Date()),
                        .text(sourceCompany.id.uuidString)
                    ]
                )

                for table in companyScopedTables {
                    try tx.execute(
                        "UPDATE \(table) SET company_id = ? WHERE company_id = ?",
                        [.text(restoredCompanyId.uuidString), .text(sourceCompany.id.uuidString)]
                    )
                }

                try writeRestoreAuditEvent(db: tx, companyId: restoredCompanyId)

                try recreateLockedFinancialYearTriggers(db: tx)
                try recreateAuditImmutabilityTriggers(db: tx)
            }

            let foreignKeyIssues = try db.query("PRAGMA foreign_key_check") { _ in true }
            guard foreignKeyIssues.isEmpty else {
                throw AppError.database(.schemaMismatch("Restore left foreign-key violations in the restored company database."))
            }
        } catch {
            try? recreateLockedFinancialYearTriggers(db: db)
            try? recreateAuditImmutabilityTriggers(db: db)
            try? db.execute("PRAGMA foreign_keys = ON")
            throw error
        }
        try db.execute("PRAGMA foreign_keys = ON")
    }

    private static func validateIntegrity(db: SQLiteDatabase) throws {
        let rows = try db.query("PRAGMA integrity_check") { $0.text(0) }
        guard rows.count == 1, rows.first == "ok" else {
            throw AppError.database(.schemaMismatch("Restore integrity check failed; original company was kept."))
        }
    }

    private static func validatePreparedCompany(db: SQLiteDatabase, companyId: Company.ID, companyName: String) throws {
        let companies = try CompanyRepository(db: db).listForRegistry()
        guard companies.count == 1, let company = companies.first else {
            throw AppError.database(.schemaMismatch("Restore validation expects exactly one prepared company."))
        }
        guard company.id == companyId, company.name == companyName else {
            throw AppError.database(.schemaMismatch("Restore validation found mismatched company metadata."))
        }
        let foreignKeyIssues = try db.query("PRAGMA foreign_key_check") { _ in true }
        guard foreignKeyIssues.isEmpty else {
            throw AppError.database(.schemaMismatch("Restore validation found foreign-key violations."))
        }
        let overlappingYears: [String] = try db.query(
            """
            SELECT DISTINCT fy1.label
            FROM avelo_financial_years fy1
            JOIN avelo_financial_years fy2
              ON fy1.company_id = fy2.company_id
             AND fy1.id <> fy2.id
             AND NOT (fy1.end_date < fy2.start_date OR fy1.start_date > fy2.end_date)
            WHERE fy1.company_id = ?
            ORDER BY fy1.start_date ASC, fy1.created_at ASC, fy1.id ASC
            """,
            bind: [.text(companyId.uuidString)]
        ) { $0.text(0) }
        guard overlappingYears.isEmpty else {
            throw AppError.database(.schemaMismatch("Restore validation found overlapping financial years: \(overlappingYears.joined(separator: ", "))."))
        }
    }

    private static func writeRestoreAuditEvent(db: SQLiteDatabase, companyId: Company.ID) throws {
        try AuditService(db: db, companyId: companyId).record(
            action: .backupImported,
            entityType: "company",
            entityId: companyId.uuidString,
            reason: "Restore from backup"
        )
    }

    private static func dropAuditImmutabilityTriggers(db: SQLiteDatabase) throws {
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_update")
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_delete")
    }

    private static func recreateAuditImmutabilityTriggers(db: SQLiteDatabase) throws {
        for sql in auditImmutabilityTriggerSQL {
            try db.execute(sql)
        }
    }

    private static func dropLockedFinancialYearTriggers(db: SQLiteDatabase) throws {
        for triggerName in lockedFinancialYearTriggerNames {
            try db.execute("DROP TRIGGER IF EXISTS \(triggerName)")
        }
    }

    private static func recreateLockedFinancialYearTriggers(db: SQLiteDatabase) throws {
        for sql in lockedFinancialYearTriggerSQL {
            try db.execute(sql)
        }
    }

    static func cleanupRestoredCompanyFile(at destURL: URL, fileManager: FileManager = .default) {
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
        } catch {
            AveloRestoreLogger.error("restore cleanup failed for \(destURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
