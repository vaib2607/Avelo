import XCTest
@testable import Avelo

final class AuditTamperEvidenceTests: XCTestCase {

    private func makeAuditedCompany() throws -> (TestCompany, AuditRepository) {
        let tc = try TestCompany.make()
        let audit = AuditService(db: tc.db, companyId: tc.companyId)
        try audit.record(action: .accountCreated, entityType: "account", entityId: "A-1", reason: "first")
        try audit.record(action: .accountUpdated, entityType: "account", entityId: "A-1", reason: "second")
        try audit.record(action: .voucherPosted, entityType: "voucher", entityId: "V-1", reason: "third")
        return (tc, AuditRepository(db: tc.db))
    }

    func testVerifyIntegrityPassesForUntamperedChain() throws {
        let (tc, repo) = try makeAuditedCompany()
        try repo.verifyIntegrity(companyId: tc.companyId)
    }

    func testVerifyIntegrityDetectsMutatedAuditRow() throws {
        let (tc, repo) = try makeAuditedCompany()
        try dropAuditImmutabilityTriggers(tc.db)
        try tc.db.execute("UPDATE avelo_audit_events SET reason = 'tampered' WHERE sequence_number = 2")

        XCTAssertThrowsError(try repo.verifyIntegrity(companyId: tc.companyId)) { error in
            self.assertTamperDetected(error)
        }
    }

    func testVerifyIntegrityDetectsDeletedAuditRow() throws {
        let (tc, repo) = try makeAuditedCompany()
        try dropAuditImmutabilityTriggers(tc.db)
        try tc.db.execute("DELETE FROM avelo_audit_events WHERE sequence_number = 2")

        XCTAssertThrowsError(try repo.verifyIntegrity(companyId: tc.companyId)) { error in
            self.assertTamperDetected(error)
        }
    }

    func testVerifyIntegrityDetectsInsertedAuditRow() throws {
        let (tc, repo) = try makeAuditedCompany()
        try dropAuditImmutabilityTriggers(tc.db)
        let row2Chain = try XCTUnwrap(
            tc.db.queryOne(
                "SELECT chain_hmac FROM avelo_audit_events WHERE company_id = ? AND sequence_number = 2",
                bind: [.text(tc.companyId.uuidString)]
            ) { $0.text(0) }
        )
        try tc.db.execute("UPDATE avelo_audit_events SET sequence_number = 4 WHERE company_id = ? AND sequence_number = 3",
                          [.text(tc.companyId.uuidString)])
        try tc.db.execute(
            """
            INSERT INTO avelo_audit_events
            (id, company_id, timestamp, actor, action, entity_type, entity_id,
             snapshot_before_json, snapshot_after_json, reason, sequence_number, previous_chain_hmac, chain_hmac)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(UUID().uuidString),
                .text(tc.companyId.uuidString),
                .text(DateFormatters.formatIsoTimestamp(Date())),
                .text("attacker"),
                .text(AuditAction.accountUpdated.rawValue),
                .text("account"),
                .text("A-evil"),
                .null,
                .null,
                .text("inserted"),
                .integer(3),
                .text(row2Chain),
                .text(String(repeating: "0", count: 64))
            ]
        )

        XCTAssertThrowsError(try repo.verifyIntegrity(companyId: tc.companyId)) { error in
            self.assertTamperDetected(error)
        }
    }

    func testVerifyIntegrityDetectsReorderedAuditRows() throws {
        let (tc, repo) = try makeAuditedCompany()
        try dropAuditImmutabilityTriggers(tc.db)
        try tc.db.execute("UPDATE avelo_audit_events SET sequence_number = 99 WHERE company_id = ? AND sequence_number = 1",
                          [.text(tc.companyId.uuidString)])
        try tc.db.execute("UPDATE avelo_audit_events SET sequence_number = 1 WHERE company_id = ? AND sequence_number = 2",
                          [.text(tc.companyId.uuidString)])
        try tc.db.execute("UPDATE avelo_audit_events SET sequence_number = 2 WHERE company_id = ? AND sequence_number = 99",
                          [.text(tc.companyId.uuidString)])

        XCTAssertThrowsError(try repo.verifyIntegrity(companyId: tc.companyId)) { error in
            self.assertTamperDetected(error)
        }
    }

    func testVerifyIntegrityDetectsWholeChainRewrite() throws {
        let (tc, repo) = try makeAuditedCompany()
        try dropAuditImmutabilityTriggers(tc.db)
        try tc.db.execute("DELETE FROM avelo_audit_events WHERE company_id = ?", [.text(tc.companyId.uuidString)])
        let now = DateFormatters.formatIsoTimestamp(Date())
        for sequence in 1...2 {
            try tc.db.execute(
                """
                INSERT INTO avelo_audit_events
                (id, company_id, timestamp, actor, action, entity_type, entity_id,
                 snapshot_before_json, snapshot_after_json, reason, sequence_number, previous_chain_hmac, chain_hmac)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(tc.companyId.uuidString),
                    .text(now),
                    .text("attacker"),
                    .text(AuditAction.companyUpdated.rawValue),
                    .text("company"),
                    .text("fake-\(sequence)"),
                    .null,
                    .null,
                    .text("rewrite"),
                    .integer(Int64(sequence)),
                    sequence == 1 ? .null : .text(String(repeating: "a", count: 64)),
                    .text(String(repeating: "f", count: 64))
                ]
            )
        }

        XCTAssertThrowsError(try repo.verifyIntegrity(companyId: tc.companyId)) { error in
            self.assertTamperDetected(error)
        }
    }

    private func dropAuditImmutabilityTriggers(_ db: SQLiteDatabase) throws {
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_update")
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_audit_no_delete")
    }

    private func assertTamperDetected(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case AppError.businessRule(let message) = error else {
            return XCTFail("Expected businessRule tamper detection, got \(error)", file: file, line: line)
        }
        XCTAssertTrue(message.contains("Audit chain verification failed"), file: file, line: line)
    }
}
