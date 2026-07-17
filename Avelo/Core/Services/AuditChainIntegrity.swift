import Foundation
import CryptoKit

enum AuditChainKeyProvider {
    private static let lock = NSLock()
    private static var stores: [CompanyKeyStoring] = [CompanyKeyStore()]

    /// A single global `store` (rather than a fallback chain) meant one
    /// `DatabaseManager`/test fixture registering its key store would
    /// silently replace whatever another concurrently-running one had
    /// registered — any lookup for the *other* company would then fail with
    /// "signing key missing" even though that company's key was never lost,
    /// just no longer reachable. Each registered store is asked in turn;
    /// the first to actually have the key wins.
    static func registerStore(_ newStore: CompanyKeyStoring) {
        lock.lock()
        defer { lock.unlock() }
        // Re-registering the same store instance (e.g. a test helper calling
        // this once per test method) would otherwise grow this list without
        // bound over a long test run.
        if Mirror(reflecting: newStore).displayStyle == .class {
            let newObject = newStore as AnyObject
            if stores.contains(where: { existing in
                Mirror(reflecting: existing).displayStyle == .class
                    && (existing as AnyObject) === newObject
            }) {
                return
            }
        }
        stores.insert(newStore, at: 0)
    }

    static func signingKey(companyId: Company.ID) throws -> SymmetricKey {
        let currentStores: [CompanyKeyStoring] = {
            lock.lock()
            defer { lock.unlock() }
            return stores
        }()
        var companyKey: Data?
        for store in currentStores {
            if let found = try store.retrieve(companyId: companyId) {
                companyKey = found
                break
            }
        }
        guard let companyKey else {
            throw AppError.database(.missingEncryptionKey("Audit signing key is missing for company \(companyId.uuidString)."))
        }
        let baseKey = SymmetricKey(data: companyKey)
        let label = Data("avelo-audit-chain-v1".utf8)
        let derived = HMAC<SHA256>.authenticationCode(for: label, using: baseKey)
        return SymmetricKey(data: Data(derived))
    }
}

struct AuditChainIntegrity: Sendable {
    struct AppendState: Sendable {
        let sequenceNumber: Int64
        let previousChainHMAC: String?
        let chainHMAC: String
    }

    /// Builds consecutive chain states for one company while a caller holds a
    /// database write transaction. Resolving the previous tip and signing key
    /// once is materially faster for imports without relaxing any audit-chain
    /// link or signature guarantees.
    struct BatchAppender {
        private let integrity: AuditChainIntegrity
        private let companyId: Company.ID
        private let signingKey: SymmetricKey
        private let encoder: JSONEncoder
        private var previousSequence: Int64
        private var previousChainHMAC: String?

        init(integrity: AuditChainIntegrity, companyId: Company.ID) throws {
            self.integrity = integrity
            self.companyId = companyId
            let previous = try integrity.latestState(companyId: companyId)
            self.previousSequence = previous?.sequenceNumber ?? 0
            self.previousChainHMAC = previous?.chainHMAC
            self.signingKey = try AuditChainKeyProvider.signingKey(companyId: companyId)
            self.encoder = AuditChainIntegrity.makePayloadEncoder()
        }

        mutating func nextState(for event: AuditEvent) throws -> AppendState {
            guard event.companyId == companyId else {
                throw AppError.businessRule("Audit batches may contain events for only one company.")
            }
            let sequenceNumber = try CheckedMath.add(
                previousSequence,
                1,
                context: "advancing the audit sequence"
            )
            let previousHMAC = previousChainHMAC
            let chainHMAC = try integrity.signedHMAC(
                for: integrity.payload(for: event, sequenceNumber: sequenceNumber, previousChainHMAC: previousHMAC),
                using: signingKey,
                encoder: encoder
            )
            previousSequence = sequenceNumber
            previousChainHMAC = chainHMAC
            return AppendState(
                sequenceNumber: sequenceNumber,
                previousChainHMAC: previousHMAC,
                chainHMAC: chainHMAC
            )
        }
    }

    private struct Payload: Encodable {
        let sequenceNumber: Int64
        let previousChainHMAC: String?
        let id: String
        let companyId: String
        let timestamp: String
        let actor: String
        let action: String
        let entityType: String
        let entityId: String
        let snapshotBeforeJson: String?
        let snapshotAfterJson: String?
        let reason: String?
    }

    private struct PersistedRow: Sendable {
        let id: String
        let companyId: String
        let timestamp: String
        let actor: String
        let action: String
        let entityType: String
        let entityId: String
        let snapshotBeforeJson: String?
        let snapshotAfterJson: String?
        let reason: String?
        let sequenceNumber: Int64
        let previousChainHMAC: String?
        let chainHMAC: String
    }

    let db: SQLiteDatabase

    func nextState(for event: AuditEvent) throws -> AppendState {
        var appender = try makeBatchAppender(for: event.companyId)
        return try appender.nextState(for: event)
    }

    func makeBatchAppender(for companyId: Company.ID) throws -> BatchAppender {
        try BatchAppender(integrity: self, companyId: companyId)
    }

    private func latestState(companyId: Company.ID) throws -> (sequenceNumber: Int64, chainHMAC: String)? {
        try db.queryOne(
            """
            SELECT sequence_number, chain_hmac
            FROM avelo_audit_events
            WHERE company_id = ?
            ORDER BY sequence_number DESC
            LIMIT 1
            """,
            bind: [.text(companyId.uuidString)]
        ) { row in
            (sequenceNumber: try row.requiredInt("sequence_number"), chainHMAC: try row.requiredText("chain_hmac"))
        }
    }

    func verify(companyId: Company.ID) throws {
        let rows: [PersistedRow] = try db.query(
            """
            SELECT id, company_id, timestamp, actor, action, entity_type, entity_id,
                   snapshot_before_json, snapshot_after_json, reason,
                   sequence_number, previous_chain_hmac, chain_hmac
            FROM avelo_audit_events
            WHERE company_id = ?
            ORDER BY sequence_number ASC
            """,
            bind: [.text(companyId.uuidString)]
        ) { row in
            PersistedRow(
                id: try row.requiredText("id"),
                companyId: try row.requiredText("company_id"),
                timestamp: try row.requiredText("timestamp"),
                actor: try row.requiredText("actor"),
                action: try row.requiredText("action"),
                entityType: try row.requiredText("entity_type"),
                entityId: try row.requiredText("entity_id"),
                snapshotBeforeJson: try row.checkedOptionalText("snapshot_before_json"),
                snapshotAfterJson: try row.checkedOptionalText("snapshot_after_json"),
                reason: try row.checkedOptionalText("reason"),
                sequenceNumber: try row.requiredInt("sequence_number"),
                previousChainHMAC: try row.checkedOptionalText("previous_chain_hmac"),
                chainHMAC: try row.requiredText("chain_hmac")
            )
        }

        let signingKey = try AuditChainKeyProvider.signingKey(companyId: companyId)
        let encoder = Self.makePayloadEncoder()
        var expectedSequence: Int64 = 1
        var previousChainHMAC: String?
        for (index, row) in rows.enumerated() {
            if row.sequenceNumber != expectedSequence {
                throw AppError.businessRule("Audit chain verification failed: expected sequence \(expectedSequence), found \(row.sequenceNumber).")
            }
            if row.previousChainHMAC != previousChainHMAC {
                throw AppError.businessRule("Audit chain verification failed at sequence \(row.sequenceNumber): previous link mismatch.")
            }
            let expectedHMAC = try signedHMAC(
                for: Payload(
                    sequenceNumber: row.sequenceNumber,
                    previousChainHMAC: previousChainHMAC,
                    id: row.id,
                    companyId: row.companyId,
                    timestamp: row.timestamp,
                    actor: row.actor,
                    action: row.action,
                    entityType: row.entityType,
                    entityId: row.entityId,
                    snapshotBeforeJson: row.snapshotBeforeJson,
                    snapshotAfterJson: row.snapshotAfterJson,
                    reason: row.reason
                ),
                using: signingKey,
                encoder: encoder
            )
            if row.chainHMAC != expectedHMAC {
                throw AppError.businessRule("Audit chain verification failed at sequence \(row.sequenceNumber): signature mismatch.")
            }
            if index < rows.count - 1 {
                expectedSequence = try CheckedMath.add(
                    expectedSequence,
                    1,
                    context: "verifying the audit sequence"
                )
            }
            previousChainHMAC = row.chainHMAC
        }
    }

    func appendStateForMigration(
        companyId: Company.ID,
        id: String,
        timestamp: String,
        actor: String,
        action: String,
        entityType: String,
        entityId: String,
        snapshotBeforeJson: String?,
        snapshotAfterJson: String?,
        reason: String?,
        previousSequence: Int64,
        previousChainHMAC: String?
    ) throws -> AppendState {
        let sequenceNumber = try CheckedMath.add(
            previousSequence,
            1,
            context: "advancing the audit sequence during migration"
        )
        let payload = Payload(
            sequenceNumber: sequenceNumber,
            previousChainHMAC: previousChainHMAC,
            id: id,
            companyId: companyId.uuidString,
            timestamp: timestamp,
            actor: actor,
            action: action,
            entityType: entityType,
            entityId: entityId,
            snapshotBeforeJson: snapshotBeforeJson,
            snapshotAfterJson: snapshotAfterJson,
            reason: reason
        )
        let chainHMAC = try signedHMAC(for: payload, companyId: companyId)
        return AppendState(sequenceNumber: sequenceNumber, previousChainHMAC: previousChainHMAC, chainHMAC: chainHMAC)
    }

    private func payload(for event: AuditEvent, sequenceNumber: Int64, previousChainHMAC: String?) -> Payload {
        Payload(
            sequenceNumber: sequenceNumber,
            previousChainHMAC: previousChainHMAC,
            id: event.id.uuidString,
            companyId: event.companyId.uuidString,
            timestamp: DateFormatters.formatIsoTimestamp(event.timestamp),
            actor: event.actor,
            action: event.action.rawValue,
            entityType: event.entityType,
            entityId: event.entityId,
            snapshotBeforeJson: event.snapshotBeforeJson,
            snapshotAfterJson: event.snapshotAfterJson,
            reason: event.reason
        )
    }

    private static func makePayloadEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func signedHMAC(for payload: Payload, companyId: Company.ID) throws -> String {
        let key = try AuditChainKeyProvider.signingKey(companyId: companyId)
        return try signedHMAC(for: payload, using: key, encoder: Self.makePayloadEncoder())
    }

    private func signedHMAC(for payload: Payload, using key: SymmetricKey, encoder: JSONEncoder) throws -> String {
        let payloadData = try encoder.encode(payload)
        let signature = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
        return Data(signature).map { String(format: "%02x", $0) }.joined()
    }
}
