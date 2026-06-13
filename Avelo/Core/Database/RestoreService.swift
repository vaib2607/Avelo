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
        "avelo_stock_movements",
        "avelo_payroll_employees",
        "avelo_payroll_entries",
        "avelo_bill_allocations",
        "avelo_cheques",
        "avelo_tds_records",
        "avelo_tcs_records",
        "avelo_audit_events",
        "avelo_voucher_sequences",
        "avelo_voucher_templates",
        "avelo_bank_reconciliations"
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
        "trg_avelo_lines_fy_locked_insert",
        "trg_avelo_lines_fy_locked_update",
        "trg_avelo_lines_fy_locked_delete"
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
        BEGIN
            SELECT RAISE(ABORT, 'Financial year is locked; voucher edits are not allowed');
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
        """
    ]

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func restore(from sourceURL: URL) async throws -> CompanyRegistryEntry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            AveloRestoreLogger.error("restore source missing: \(sourceURL.path, privacy: .public)")
            throw AppError.notFound("Backup file not found")
        }

        let tempFile = sourceURL
        let manifestURL: URL = {
            if sourceURL.pathExtension == "manifest.json" {
                return sourceURL
            }
            return sourceURL.appendingPathExtension("manifest.json")
        }()

        let manifest: BackupManifest
        if fm.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            manifest = try dec.decode(BackupManifest.self, from: data)
        } else {
            manifest = BackupManifest(
                schemaVersion: SchemaVersion.current.rawValue,
                companyName: sourceURL.deletingPathExtension().lastPathComponent,
                exportedAt: Date(),
                checksumSHA256: "",
                originalFileName: sourceURL.lastPathComponent
            )
        }

        let data = try Data(contentsOf: tempFile)
        if !manifest.checksumSHA256.isEmpty {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if hex != manifest.checksumSHA256 {
                AveloRestoreLogger.error("restore checksum mismatch for \(sourceURL.lastPathComponent, privacy: .public)")
                throw AppError.database(.checksumMismatch)
            }
        }

        let registryEntries = try await manager.listCompanies()
        if registryEntries.contains(where: { $0.name.caseInsensitiveCompare(manifest.companyName) == .orderedSame }) {
            AveloRestoreLogger.error("duplicate restore name rejected: \(manifest.companyName, privacy: .public)")
            throw AppError.businessRule("A company named \"\(manifest.companyName)\" already exists. Rename or remove the existing company before restoring this backup.")
        }

        let newId = UUID()
        let destURL = manager.companiesDirectory.appendingPathComponent("\(newId.uuidString).sqlite")
        if fm.fileExists(atPath: destURL.path) {
            do {
                try fm.removeItem(at: destURL)
            } catch {
                throw AppError.fileSystem("Unable to replace existing restored company file at \(destURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            try fm.copyItem(at: tempFile, to: destURL)
        } catch {
            AveloRestoreLogger.error("restore copy failed to \(destURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to copy backup into restored company file at \(destURL.lastPathComponent): \(error.localizedDescription)")
        }

        do {
            let db = try SQLiteDatabase(path: destURL.path)
            defer { db.close() }
            try Self.validateIntegrity(db: db)
            let current = db.userVersion()
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

            let entry = CompanyRegistryEntry(
                id: newId,
                name: manifest.companyName,
                sqliteFileName: destURL.lastPathComponent,
                lastOpenedAt: nil,
                createdAt: Date()
            )
            try await manager.registerCompany(entry)
            return entry
        } catch {
            AveloRestoreLogger.error("restore failed, cleaning up \(destURL.path, privacy: .public)")
            Self.cleanupRestoredCompanyFile(at: destURL, fileManager: fm)
            throw error
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
            try recreateLockedFinancialYearTriggers(db: db)
            try recreateAuditImmutabilityTriggers(db: db)
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
