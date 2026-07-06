import Foundation

public final class AuditService: Sendable {

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
                       snapshotBefore: Encodable? = nil,
                       snapshotAfter: Encodable? = nil,
                       reason: String? = nil) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let beforeJson: String? = try snapshotBefore.flatMap { try Self.encode($0, encoder: enc) }
        let afterJson:  String? = try snapshotAfter.flatMap  { try Self.encode($0, encoder: enc) }
        let event = AuditEvent(
            companyId: companyId,
            action: action,
            entityType: entityType,
            entityId: entityId,
            snapshotBeforeJson: beforeJson,
            snapshotAfterJson: afterJson,
            reason: reason
        )
        try repository.append(event)
    }

    public func list(filter: AuditRepository.Filter) throws -> [AuditEvent] {
        try repository.list(filter: filter)
    }

    public func verifyIntegrity() throws {
        try repository.verifyIntegrity(companyId: companyId)
    }

    private static func encode(_ value: Encodable, encoder: JSONEncoder) throws -> String? {
        let data = try encoder.encode(AnyEnc(value))
        return String(data: data, encoding: .utf8)
    }
}

private struct AnyEnc: Encodable {
    let wrapped: Encodable
    init(_ wrapped: Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws {
        try wrapped.encode(to: encoder)
    }
}
