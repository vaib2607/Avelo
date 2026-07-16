import Foundation

public final class AuditService: Sendable {

    /// An audit event prepared by a service layer. `recordBatch` serializes
    /// all snapshots with one encoder, then appends the resulting events as a
    /// single consecutive chain segment.
    public struct Record {
        public let timestamp: Date
        public let actor: String
        public let action: AuditAction
        public let entityType: String
        public let entityId: String
        public let snapshotBefore: (any Encodable)?
        public let snapshotAfter: (any Encodable)?
        public let reason: String?

        public init(timestamp: Date = Date(),
                    actor: String = "user",
                    action: AuditAction,
                    entityType: String,
                    entityId: String,
                    snapshotBefore: (any Encodable)? = nil,
                    snapshotAfter: (any Encodable)? = nil,
                    reason: String? = nil) {
            self.timestamp = timestamp
            self.actor = actor
            self.action = action
            self.entityType = entityType
            self.entityId = entityId
            self.snapshotBefore = snapshotBefore
            self.snapshotAfter = snapshotAfter
            self.reason = reason
        }
    }

    public let repository: AuditRepository
    public let companyId: Company.ID
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = AuditRepository(db: db)
        self.companyId = companyId
    }

    public func record(action: AuditAction,
                       entityType: String,
                       entityId: String,
                       snapshotBefore: (any Encodable)? = nil,
                       snapshotAfter: (any Encodable)? = nil,
                       reason: String? = nil) throws {
        try recordBatch([
            Record(
                action: action,
                entityType: entityType,
                entityId: entityId,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotAfter,
                reason: reason
            )
        ])
    }

    public func recordBatch(_ records: [Record]) throws {
        guard !records.isEmpty else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let events = try records.map { record in
            AuditEvent(
                companyId: companyId,
                timestamp: record.timestamp,
                actor: record.actor,
                action: record.action,
                entityType: record.entityType,
                entityId: record.entityId,
                snapshotBeforeJson: try Self.encode(record.snapshotBefore, encoder: enc),
                snapshotAfterJson: try Self.encode(record.snapshotAfter, encoder: enc),
                reason: record.reason
            )
        }
        try repository.appendBatch(events)
    }

    public func list(filter: AuditRepository.Filter) throws -> [AuditEvent] {
        try repository.list(filter: filter)
    }

    public func verifyIntegrity() throws {
        try repository.verifyIntegrity(companyId: companyId)
    }

    private static func encode(_ value: (any Encodable)?, encoder: JSONEncoder) throws -> String? {
        guard let value else { return nil }
        let data = try encoder.encode(AnyEnc(value))
        return String(data: data, encoding: .utf8)
    }
}

private struct AnyEnc: Encodable {
    let wrapped: any Encodable
    init(_ wrapped: any Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws {
        try wrapped.encode(to: encoder)
    }
}
