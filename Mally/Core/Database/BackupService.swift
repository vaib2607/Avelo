import Foundation
import CryptoKit

public struct BackupService: Sendable {

    public let manager: DatabaseManager

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func export(companyId: UUID,
                       companyName: String,
                       to destinationURL: URL) async throws -> BackupManifest {
        let sourceURL = manager.companiesDirectory.appendingPathComponent("\(companyId.uuidString).sqlite")
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
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
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)

        let data = try Data(contentsOf: destinationURL)
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
        let json = try enc.encode(manifest)
        try json.write(to: manifestURL)
        return manifest
    }
}
