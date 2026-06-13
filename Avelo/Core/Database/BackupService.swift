import Foundation
import CryptoKit
import os

private let AveloBackupLogger = Logger(subsystem: "com.avelo.desktop", category: "backup")

public struct BackupService: Sendable {

    public let manager: DatabaseManager

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func export(companyId: UUID,
                       companyName: String,
                       to destinationURL: URL) async throws -> BackupManifest {
        let sourceURL = try await manager.companyFileURL(id: companyId)
        let fm = FileManager.default
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
        if fm.fileExists(atPath: destinationURL.path) {
            do {
                try fm.removeItem(at: destinationURL)
            } catch {
                AveloBackupLogger.error("backup replace failed: \(destinationURL.path, privacy: .public)")
                throw AppError.fileSystem("Unable to replace existing backup file at \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            try fm.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            AveloBackupLogger.error("backup copy failed: \(destinationURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to write backup file at \(destinationURL.lastPathComponent): \(error.localizedDescription)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: destinationURL)
        } catch {
            AveloBackupLogger.error("backup readback failed: \(destinationURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to read written backup file at \(destinationURL.lastPathComponent): \(error.localizedDescription)")
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let manifest = BackupManifest(
            schemaVersion: SchemaVersion.current.rawValue,
            companyName: companyName,
            exportedAt: Date(),
            checksumSHA256: hex,
            originalFileName: sourceURL.lastPathComponent
        )
        let manifestURL = destinationURL.appendingPathExtension("manifest.json")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let json: Data
        do {
            json = try enc.encode(manifest)
        } catch {
            AveloBackupLogger.error("backup manifest encode failed: \(destinationURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to encode backup manifest for \(destinationURL.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            try json.write(to: manifestURL)
        } catch {
            AveloBackupLogger.error("backup manifest write failed: \(manifestURL.path, privacy: .public)")
            throw AppError.fileSystem("Unable to write backup manifest at \(manifestURL.lastPathComponent): \(error.localizedDescription)")
        }
        return manifest
    }
}
