import Foundation

public struct CompanyRegistryEntry: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public var name: String
    public var sqliteFileName: String
    public var lastOpenedAt: Date?
    public let createdAt: Date

    public init(id: ID = UUID(),
                name: String,
                sqliteFileName: String,
                lastOpenedAt: Date? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sqliteFileName = sqliteFileName
        self.lastOpenedAt = lastOpenedAt
        self.createdAt = createdAt
    }
}

public struct BackupManifest: Codable, Hashable, Sendable {
    public var manifestVersion: Int
    public var schemaVersion: Int
    public var companyName: String
    public var exportedAt: Date
    public var checksumSHA256: String
    public var originalFileName: String
    public var byteCount: Int64

    public init(manifestVersion: Int = 1,
                schemaVersion: Int,
                companyName: String,
                exportedAt: Date,
                checksumSHA256: String,
                originalFileName: String,
                byteCount: Int64 = 0) {
        self.manifestVersion = manifestVersion
        self.schemaVersion = schemaVersion
        self.companyName = companyName
        self.exportedAt = exportedAt
        self.checksumSHA256 = checksumSHA256
        self.originalFileName = originalFileName
        self.byteCount = byteCount
    }
}
