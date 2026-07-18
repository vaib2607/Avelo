import Foundation

/// Extends the immutable audit taxonomy for canonical inventory cost and
/// partial-return workflows. The tracks themselves were introduced by V027;
/// this migration deliberately does not reinterpret historic values.
public struct MigrationV030: Migration {
    public let version: SchemaVersion = .v30
    public let description = "Add canonical inventory allocation and return audit actions"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_update;")
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_delete;")
        try db.execute("ALTER TABLE avelo_audit_events RENAME TO avelo_audit_events_v29;")
        try db.execute(
            """
            CREATE TABLE avelo_audit_events (
                id TEXT NOT NULL PRIMARY KEY,
                company_id TEXT NOT NULL REFERENCES avelo_companies(id),
                timestamp TEXT NOT NULL,
                actor TEXT NOT NULL DEFAULT 'user',
                action TEXT NOT NULL CHECK(action IN (
                    'companyCreated','companyUpdated','financialYearCreated','financialYearLocked','financialYearClosed','financialYearUnlocked','financialYearReopened',
                    'accountCreated','accountUpdated','accountDisabled','accountGroupCreated','accountGroupUpdated','accountGroupDeleted',
                    'voucherPosted','voucherEdited','voucherReversed','voucherCancelled','chequeBounced','chequeRepresented','openingBalancePosted',
                    'stockItemCreated','stockItemUpdated','stockItemDisabled','stockMovementPosted','stockMovementReversed',
                    'inventoryCostAllocated','itemInvoiceReturnPosted',
                    'payrollEmployeeCreated','payrollEmployeeUpdated','payrollEmployeeTerminated','salaryPosted',
                    'backupExported','backupImported','companySwitched','financialYearSwitched','bankStatementImported','bankStatementLineCleared',
                    'inventoryOrderCreated','inventoryOrderFulfilled','inventoryOrderStatusChanged','inventoryReorderLevelSet',
                    'billOfMaterialsCreated','billOfMaterialsUpdated','voucherTemplateSaved','gstReportExported','invoicePDFExported'
                )),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                snapshot_before_json TEXT,
                snapshot_after_json TEXT,
                reason TEXT,
                sequence_number INTEGER NOT NULL,
                previous_chain_hmac TEXT,
                chain_hmac TEXT NOT NULL,
                CHECK(length(trim(action)) > 0), CHECK(length(trim(entity_type)) > 0), CHECK(length(trim(entity_id)) > 0),
                CHECK(sequence_number > 0), CHECK(previous_chain_hmac IS NULL OR length(previous_chain_hmac) = 64), CHECK(length(chain_hmac) = 64)
            );
            """
        )
        try db.execute(
            """
            INSERT INTO avelo_audit_events
            SELECT id, company_id, timestamp, actor, action, entity_type, entity_id, snapshot_before_json, snapshot_after_json, reason,
                   sequence_number, previous_chain_hmac, chain_hmac
            FROM avelo_audit_events_v29 ORDER BY company_id ASC, sequence_number ASC;
            """
        )
        try db.execute("DROP TABLE avelo_audit_events_v29;")
        try db.execute("CREATE INDEX idx_avelo_audit_entity ON avelo_audit_events(company_id, entity_type, entity_id);")
        try db.execute("CREATE INDEX idx_avelo_audit_time ON avelo_audit_events(company_id, timestamp);")
        try db.execute("CREATE UNIQUE INDEX idx_avelo_audit_sequence ON avelo_audit_events(company_id, sequence_number);")
        try db.execute("CREATE TRIGGER trg_avelo_audit_no_update BEFORE UPDATE ON avelo_audit_events BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;")
        try db.execute("CREATE TRIGGER trg_avelo_audit_no_delete BEFORE DELETE ON avelo_audit_events BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;")
    }
}
