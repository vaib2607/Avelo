import Foundation
import CryptoKit

public struct RestoreService: Sendable {

    public let manager: DatabaseManager

    public init(manager: DatabaseManager) {
        self.manager = manager
    }

    public func restore(from sourceURL: URL) async throws -> CompanyRegistryEntry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw AppError.notFound("Backup file not found")
        }

        let manifestURL: URL
        let tempFile: URL
        if sourceURL.pathExtension == "mallybackup" {
            manifestURL = sourceURL.appendingPathExtension("manifest.json")
            tempFile = sourceURL
        } else {
            manifestURL = sourceURL
            tempFile = sourceURL.deletingPathExtension()
        }

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

        let newId = UUID()
        let destURL = manager.companiesDirectory.appendingPathComponent("\(newId.uuidString).sqlite")
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: tempFile, to: destURL)

        let db = try SQLiteDatabase(path: destURL.path)
        defer { db.close() }
        let current = db.userVersion()
        if current < SchemaVersion.current.rawValue {
            try MigrationRunner().runMigrations(on: db)
        }

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
}
