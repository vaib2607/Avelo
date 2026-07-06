import Foundation

public struct MigrationV007: Migration {
    public let version: SchemaVersion = .v7
    public let description = "Add voucher cancellation state and metadata"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        if try !hasColumn("status", in: "avelo_vouchers", db: db) {
            try db.execute("ALTER TABLE avelo_vouchers ADD COLUMN status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','cancelled'));")
        }
        if try !hasColumn("cancelled_at", in: "avelo_vouchers", db: db) {
            try db.execute("ALTER TABLE avelo_vouchers ADD COLUMN cancelled_at TEXT;")
        }
        if try !hasColumn("cancelled_by", in: "avelo_vouchers", db: db) {
            try db.execute("ALTER TABLE avelo_vouchers ADD COLUMN cancelled_by TEXT;")
        }
        if try !hasColumn("cancellation_reason", in: "avelo_vouchers", db: db) {
            try db.execute("ALTER TABLE avelo_vouchers ADD COLUMN cancellation_reason TEXT;")
        }
        if try !hasColumn("cancellation_voucher_id", in: "avelo_vouchers", db: db) {
            try db.execute("ALTER TABLE avelo_vouchers ADD COLUMN cancellation_voucher_id TEXT REFERENCES avelo_vouchers(id);")
        }
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_vouchers_status ON avelo_vouchers(status);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_avelo_vouchers_cancel_link ON avelo_vouchers(cancellation_voucher_id);")

        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_update;")
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_delete;")
        try db.execute("ALTER TABLE avelo_audit_events RENAME TO avelo_audit_events_old;")
        try db.execute(
            """
            CREATE TABLE avelo_audit_events (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id),
                timestamp TEXT NOT NULL,
                actor TEXT NOT NULL DEFAULT 'user',
                action TEXT NOT NULL CHECK(action IN (
                    'companyCreated','companyUpdated',
                    'financialYearCreated','financialYearLocked','financialYearClosed',
                    'accountCreated','accountUpdated','accountDisabled',
                    'voucherPosted','voucherEdited','voucherReversed','voucherCancelled',
                    'openingBalancePosted',
                    'stockItemCreated','stockItemUpdated','stockItemDisabled',
                    'stockMovementPosted','stockMovementReversed',
                    'payrollEmployeeCreated','payrollEmployeeUpdated','payrollEmployeeTerminated',
                    'salaryPosted',
                    'backupExported','backupImported',
                    'companySwitched','financialYearSwitched'
                )),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                snapshot_before_json TEXT,
                snapshot_after_json TEXT,
                reason TEXT,
                sequence_number INTEGER NOT NULL,
                previous_chain_hmac TEXT,
                chain_hmac TEXT NOT NULL,
                CHECK(length(trim(action)) > 0),
                CHECK(length(trim(entity_type)) > 0),
                CHECK(length(trim(entity_id)) > 0),
                CHECK(sequence_number > 0),
                CHECK(previous_chain_hmac IS NULL OR length(previous_chain_hmac) = 64),
                CHECK(length(chain_hmac) = 64)
            );
            """
        )
        let rows: [(String, String, String, String, String, String, String, String?, String?, String?)] = try db.query(
            """
            SELECT id, company_id, timestamp, actor, action, entity_type, entity_id,
                   snapshot_before_json, snapshot_after_json, reason
            FROM avelo_audit_events_old
            ORDER BY company_id ASC, timestamp ASC, id ASC
            """
        ) { row in
            (
                row.text("id"),
                row.text("company_id"),
                row.text("timestamp"),
                row.text("actor"),
                row.text("action"),
                row.text("entity_type"),
                row.text("entity_id"),
                row.optionalText("snapshot_before_json"),
                row.optionalText("snapshot_after_json"),
                row.optionalText("reason")
            )
        }
        var stateByCompany: [String: (sequence: Int64, chain: String?)] = [:]
        let integrity = AuditChainIntegrity(db: db)
        for row in rows {
            let companyId = try UUIDParsing.required(row.1, field: "avelo_audit_events.company_id")
            let prior = stateByCompany[row.1] ?? (0, nil)
            let next = try integrity.appendStateForMigration(
                companyId: companyId,
                id: row.0,
                timestamp: row.2,
                actor: row.3,
                action: row.4,
                entityType: row.5,
                entityId: row.6,
                snapshotBeforeJson: row.7,
                snapshotAfterJson: row.8,
                reason: row.9,
                previousSequence: prior.sequence,
                previousChainHMAC: prior.chain
            )
            try db.execute(
                """
                INSERT INTO avelo_audit_events
                (id, company_id, timestamp, actor, action, entity_type, entity_id,
                 snapshot_before_json, snapshot_after_json, reason, sequence_number, previous_chain_hmac, chain_hmac)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(row.0),
                    .text(row.1),
                    .text(row.2),
                    .text(row.3),
                    .text(row.4),
                    .text(row.5),
                    .text(row.6),
                    .optionalText(row.7),
                    .optionalText(row.8),
                    .optionalText(row.9),
                    .integer(next.sequenceNumber),
                    .optionalText(next.previousChainHMAC),
                    .text(next.chainHMAC)
                ]
            )
            stateByCompany[row.1] = (next.sequenceNumber, next.chainHMAC)
        }
        try db.execute("DROP TABLE avelo_audit_events_old;")
        try db.execute("CREATE INDEX idx_avelo_audit_entity ON avelo_audit_events(company_id, entity_type, entity_id);")
        try db.execute("CREATE INDEX idx_avelo_audit_time ON avelo_audit_events(company_id, timestamp);")
        try db.execute("CREATE UNIQUE INDEX idx_avelo_audit_sequence ON avelo_audit_events(company_id, sequence_number);")
        try db.execute("CREATE TRIGGER trg_avelo_audit_no_update BEFORE UPDATE ON avelo_audit_events BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;")
        try db.execute("CREATE TRIGGER trg_avelo_audit_no_delete BEFORE DELETE ON avelo_audit_events BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;")
    }

    private func hasColumn(_ column: String, in table: String, db: SQLiteDatabase) throws -> Bool {
        let columns: [String] = try db.query("PRAGMA table_info(\(table))") { $0.text("name") }
        return columns.contains(column)
    }
}
