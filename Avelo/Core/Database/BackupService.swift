import Foundation
import CryptoKit
import os

private let AveloBackupLogger = Logger(subsystem: "com.avelo.desktop", category: "backup")

public struct BackupService: Sendable {

    public let manager: DatabaseManager
    private let activityController: any LongOperationActivityControlling

    public init(manager: DatabaseManager,
                activityController: any LongOperationActivityControlling = ProcessInfoLongOperationActivityController()) {
        self.manager = manager
        self.activityController = activityController
    }

    public func export(companyId: UUID,
                       companyName: String,
                       to destinationURL: URL) async throws -> BackupManifest {
        try await activityController.perform(reason: "Avelo backup export") {
            let sourceURL = try await manager.companyFileURL(id: companyId)
            let fm = FileManager.default
            let tempURL = destinationURL.deletingLastPathComponent()
                .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
            let manifestURL = destinationURL.appendingPathExtension("manifest.json")
            let manifestTempURL = manifestURL.deletingLastPathComponent()
                .appendingPathComponent(".\(manifestURL.lastPathComponent).\(UUID().uuidString).tmp")
            defer {
                try? fm.removeItem(at: tempURL)
                try? fm.removeItem(at: manifestTempURL)
            }
            guard fm.fileExists(atPath: sourceURL.path) else {
                AveloBackupLogger.error("backup source missing: \(sourceURL.path, privacy: .public)")
                throw AppError.notFound("Source company file missing")
            }
            if let handle = await manager.openHandle(id: companyId) {
                try handle.db.checkpoint()
            } else {
                let tempHandle = try await manager.openCompany(id: companyId)
                try tempHandle.db.checkpoint()
                await manager.closeCompany(id: companyId)
            }
            do {
                try fm.copyItem(at: sourceURL, to: tempURL)
            } catch {
                AveloBackupLogger.error("backup temp copy failed: \(tempURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to stage backup file at \(tempURL.lastPathComponent): \(error.localizedDescription)")
            }

            let data: Data
            do {
                data = try Data(contentsOf: tempURL)
            } catch {
                AveloBackupLogger.error("backup readback failed: \(tempURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to read staged backup file at \(tempURL.lastPathComponent): \(error.localizedDescription)")
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            let manifest = BackupManifest(
                manifestVersion: 1,
                schemaVersion: SchemaVersion.current.rawValue,
                companyName: companyName,
                exportedAt: Date(),
                checksumSHA256: hex,
                originalFileName: sourceURL.lastPathComponent,
                byteCount: Int64(data.count)
            )
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let json: Data
            do {
                json = try enc.encode(manifest)
            } catch {
                AveloBackupLogger.error("backup manifest encode failed: \(tempURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to encode backup manifest for \(tempURL.lastPathComponent): \(error.localizedDescription)")
            }
            do {
                try Self.replaceItemAtomically(tempURL: tempURL, destinationURL: destinationURL, fileManager: fm)
            } catch {
                AveloBackupLogger.error("backup atomic replace failed: \(destinationURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to replace backup file at \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            }
            do {
                try json.write(to: manifestTempURL, options: .atomic)
                try Self.replaceItemAtomically(tempURL: manifestTempURL, destinationURL: manifestURL, fileManager: fm)
            } catch {
                AveloBackupLogger.error("backup manifest write failed: \(manifestURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to write backup manifest at \(manifestURL.lastPathComponent): \(error.localizedDescription)")
            }
            let existingHandle = await manager.openHandle(id: companyId)
            let auditHandle: CompanyHandle
            if let existingHandle {
                auditHandle = existingHandle
            } else {
                auditHandle = try await manager.openCompany(id: companyId)
            }
            do {
                try AuditService(db: auditHandle.db, companyId: companyId).record(
                    action: .backupExported,
                    entityType: "company",
                    entityId: companyId.uuidString,
                    snapshotAfter: manifest,
                    reason: "Backup exported as \(destinationURL.lastPathComponent)"
                )
            } catch {
                if existingHandle == nil {
                    await manager.closeCompany(id: companyId)
                }
                // A backup without its required audit event is not complete.
                // Remove both externally visible artifacts before failing.
                try? fm.removeItem(at: destinationURL)
                try? fm.removeItem(at: manifestURL)
                throw error
            }
            if existingHandle == nil {
                await manager.closeCompany(id: companyId)
            }
            return manifest
        }
    }

    private static func replaceItemAtomically(tempURL: URL, destinationURL: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }
    }
}
