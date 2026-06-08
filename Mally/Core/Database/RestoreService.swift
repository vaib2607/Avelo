import Foundation
import CryptoKit

public struct RestoreService: Sendable {

    public let manager: DatabaseManager
    private static let companyScopedTables: [String] = [
        "mally_financial_years",
        "mally_account_groups",
        "mally_accounts",
        "mally_voucher_types",
        "mally_vouchers",
        "mally_ledger_lines",
        "mally_inventory_items",
        "mally_stock_movements",
        "mally_payroll_employees",
        "mally_payroll_entries",
        "mally_audit_events",
        "mally_voucher_sequences",
        "mally_voucher_templates",
        "mally_bank_reconciliations"
    ]
    private static let auditImmutabilityTriggerSQL: [String] = [
        """
        CREATE TRIGGER trg_mally_audit_no_update
        BEFORE UPDATE ON mally_audit_events
        BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
        """,
        """
        CREATE TRIGGER trg_mally_audit_no_delete
        BEFORE DELETE ON mally_audit_events
        BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
        """
    ]

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func restore(from sourceURL: URL) async throws -> CompanyRegistryEntry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
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
                throw AppError.database(.checksumMismatch)
            }
        }

        let registryEntries = try await manager.listCompanies()
        if registryEntries.contains(where: { $0.name.caseInsensitiveCompare(manifest.companyName) == .orderedSame }) {
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
            throw AppError.fileSystem("Unable to copy backup into restored company file at \(destURL.lastPathComponent): \(error.localizedDescription)")
        }

        let db = try SQLiteDatabase(path: destURL.path)
        defer { db.close() }
        let current = db.userVersion()
        if current < SchemaVersion.current.rawValue {
            try MigrationRunner().runMigrations(on: db)
        }
        try Self.prepareRestoredCompanyDatabase(
            db: db,
            restoredCompanyId: newId,
            restoredCompanyName: manifest.companyName
        )

        let entry = CompanyRegistryEntry(
            id: newId,
            name: manifest.companyName,
            sqliteFileName: destURL.lastPathComponent,
            lastOpenedAt: nil,
            createdAt: Date()
        )
        try await manager.registerCompany(entry)
        return entry
    }

    static func prepareRestoredCompanyDatabase(
        db: SQLiteDatabase,
        restoredCompanyId: Company.ID,
        restoredCompanyName: String
    ) throws {
        let sourceCompanies = try CompanyRepository(db: db).listForRegistry()
        guard sourceCompanies.count == 1, let sourceCompany = sourceCompanies.first else {
            throw AppError.database(.schemaMismatch("Restore expects exactly one company per backup file."))
        }
        if sourceCompany.id == restoredCompanyId {
            try writeRestoreAuditEvent(db: db, companyId: restoredCompanyId)
            return
        }

        try db.execute("PRAGMA foreign_keys = OFF")
        do {
            try dropAuditImmutabilityTriggers(db: db)
            try db.write { tx in
                try tx.execute(
                    "UPDATE mally_companies SET id = ?, name = ?, updated_at = ? WHERE id = ?",
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
            }
            try recreateAuditImmutabilityTriggers(db: db)

            let foreignKeyIssues = try db.query("PRAGMA foreign_key_check") { _ in true }
            guard foreignKeyIssues.isEmpty else {
                throw AppError.database(.schemaMismatch("Restore left foreign-key violations in the restored company database."))
            }
        } catch {
            try? recreateAuditImmutabilityTriggers(db: db)
            try? db.execute("PRAGMA foreign_keys = ON")
            throw error
        }
        try db.execute("PRAGMA foreign_keys = ON")
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
        try db.execute("DROP TRIGGER IF EXISTS trg_mally_audit_no_update")
        try db.execute("DROP TRIGGER IF EXISTS trg_mally_audit_no_delete")
    }

    private static func recreateAuditImmutabilityTriggers(db: SQLiteDatabase) throws {
        for sql in auditImmutabilityTriggerSQL {
            try db.execute(sql)
        }
    }
}
