import Foundation

public struct AuditRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func append(_ event: AuditEvent) throws {
        try db.execute(
            """
            INSERT INTO mally_audit_events
            (id, company_id, timestamp, actor, action, entity_type, entity_id,
             snapshot_before_json, snapshot_after_json, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(event.id.uuidString),
                .text(event.companyId.uuidString),
                .timestamp(event.timestamp),
                .text(event.actor),
                .text(event.action.rawValue),
                .text(event.entityType),
                .text(event.entityId),
                .optionalText(event.snapshotBeforeJson),
                .optionalText(event.snapshotAfterJson),
                .optionalText(event.reason)
            ]
        )
    }

    public struct Filter: Sendable {
        public var companyId: Company.ID
        public var action: AuditAction?
        public var entityType: String?
        public var entityId: String?
        public var searchText: String?
        public var fromDate: Date?
        public var toDate: Date?
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    action: AuditAction? = nil,
                    entityType: String? = nil,
                    entityId: String? = nil,
                    searchText: String? = nil,
                    fromDate: Date? = nil,
                    toDate: Date? = nil,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.action = action
            self.entityType = entityType
            self.entityId = entityId
            self.searchText = searchText
            self.fromDate = fromDate
            self.toDate = toDate
            self.limit = limit
            self.offset = offset
        }
    }

    public func list(filter: Filter) throws -> [AuditEvent] {
        var sql = """
            SELECT id, company_id, timestamp, actor, action, entity_type, entity_id,
                   snapshot_before_json, snapshot_after_json, reason
            FROM mally_audit_events
            WHERE company_id = ?
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let action = filter.action {
            sql += " AND action = ?"
            bind.append(.text(action.rawValue))
        }
        if let et = filter.entityType {
            sql += " AND entity_type = ?"
            bind.append(.text(et))
        }
        if let eid = filter.entityId {
            sql += " AND entity_id = ?"
            bind.append(.text(eid))
        }
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !search.isEmpty {
            let needle = "%\(search.lowercased())%"
            sql += """
                 AND (
                    lower(actor) LIKE ?
                    OR lower(action) LIKE ?
                    OR lower(entity_type) LIKE ?
                    OR lower(entity_id) LIKE ?
                    OR lower(COALESCE(reason, '')) LIKE ?
                    OR lower(COALESCE(snapshot_before_json, '')) LIKE ?
                    OR lower(COALESCE(snapshot_after_json, '')) LIKE ?
                 )
            """
            bind.append(contentsOf: Array(repeating: .text(needle), count: 7))
        }
        if let from = filter.fromDate {
            sql += " AND timestamp >= ?"
            bind.append(.timestamp(from))
        }
        if let to = filter.toDate {
            sql += " AND timestamp <= ?"
            bind.append(.timestamp(to))
        }
        sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
        bind.append(.integer(Int64(filter.limit)))
        bind.append(.integer(Int64(filter.offset)))
        return try db.query(sql, bind: bind) { try Self.rowToEvent($0) }
    }

    public func countForEntity(_ entityType: String, entityId: String, companyId: Company.ID) throws -> Int {
        let v: Int64? = try db.queryOne(
            "SELECT COUNT(*) FROM mally_audit_events WHERE company_id = ? AND entity_type = ? AND entity_id = ?",
            bind: [.text(companyId.uuidString), .text(entityType), .text(entityId)]
        ) { r in r.int(0) }
        return Int(v ?? 0)
    }

    static func rowToEvent(_ r: Row) throws -> AuditEvent {
        let idRaw = r.text("id")
        guard let id = UUID(uuidString: idRaw) else {
            throw AppError.database(.rowReadFailed("Invalid audit event id: \(idRaw)"))
        }
        let companyIdRaw = r.text("company_id")
        guard let companyId = UUID(uuidString: companyIdRaw) else {
            throw AppError.database(.rowReadFailed("Invalid audit company id: \(companyIdRaw)"))
        }
        let actionRaw = r.text("action")
        guard let action = AuditAction(rawValue: actionRaw) else {
            throw AppError.database(.rowReadFailed("Unknown audit action: \(actionRaw)"))
        }
        return AuditEvent(
            id: id,
            companyId: companyId,
            timestamp: r.timestamp("timestamp"),
            actor: r.text("actor"),
            action: action,
            entityType: r.text("entity_type"),
            entityId: r.text("entity_id"),
            snapshotBeforeJson: r.optionalText("snapshot_before_json"),
            snapshotAfterJson: r.optionalText("snapshot_after_json"),
            reason: r.optionalText("reason")
        )
    }
}
