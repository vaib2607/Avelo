import XCTest
@testable import Avelo

final class AuditRepositoryTests: XCTestCase {

<<<<<<< HEAD
    func testAppendBatchWritesOneContinuousVerifiableChain() throws {
        let tc = try TestCompany.make()
        let repo = AuditRepository(db: tc.db)

        try repo.append(AuditEvent(
            companyId: tc.companyId,
            action: .accountCreated,
            entityType: "account",
            entityId: "A-1"
        ))
        try repo.appendBatch([
            AuditEvent(companyId: tc.companyId, action: .accountUpdated, entityType: "account", entityId: "A-1"),
            AuditEvent(companyId: tc.companyId, action: .voucherPosted, entityType: "voucher", entityId: "V-1"),
            AuditEvent(companyId: tc.companyId, action: .voucherCancelled, entityType: "voucher", entityId: "V-1")
        ])

        try repo.verifyIntegrity(companyId: tc.companyId)
        let links: [(sequence: Int64, previous: String?, chain: String)] = try tc.db.query(
            """
            SELECT sequence_number, previous_chain_hmac, chain_hmac
            FROM avelo_audit_events
            WHERE company_id = ?
            ORDER BY sequence_number ASC
            """,
            bind: [.text(tc.companyId.uuidString)]
        ) { row in
            (row.int("sequence_number"), row.optionalText("previous_chain_hmac"), row.text("chain_hmac"))
        }
        XCTAssertEqual(links.map(\.sequence), [1, 2, 3, 4])
        XCTAssertNil(links[0].previous)
        XCTAssertEqual(links[1].previous, links[0].chain)
        XCTAssertEqual(links[2].previous, links[1].chain)
        XCTAssertEqual(links[3].previous, links[2].chain)
    }

    func testAppendBatchRejectsMixedCompanyBeforeWritingAnyEvent() throws {
        let tc = try TestCompany.make()
        let repo = AuditRepository(db: tc.db)
        let foreignCompanyId = UUID()

        XCTAssertThrowsError(try repo.appendBatch([
            AuditEvent(companyId: tc.companyId, action: .accountCreated, entityType: "account", entityId: "A-1"),
            AuditEvent(companyId: foreignCompanyId, action: .accountCreated, entityType: "account", entityId: "A-2")
        ]))

        let count = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_audit_events") { $0.int(0) }
        XCTAssertEqual(count, 0)
    }

    func testAppendBatchRollsBackWhenAnEventIdRepeats() throws {
        let tc = try TestCompany.make()
        let repo = AuditRepository(db: tc.db)
        let duplicateId = UUID()

        XCTAssertThrowsError(try repo.appendBatch([
            AuditEvent(id: duplicateId, companyId: tc.companyId, action: .accountCreated, entityType: "account", entityId: "A-1"),
            AuditEvent(id: duplicateId, companyId: tc.companyId, action: .accountUpdated, entityType: "account", entityId: "A-1")
        ]))

        let count = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_audit_events") { $0.int(0) }
        XCTAssertEqual(count, 0)
    }

=======
>>>>>>> origin/main
    func testSearchTextMatchesActorReasonAndEntity() throws {
        let tc = try TestCompany.make()
        let repo = AuditRepository(db: tc.db)

        try repo.append(
            AuditEvent(
                companyId: tc.companyId,
                actor: "reviewer",
                action: .voucherEdited,
                entityType: "voucher",
                entityId: "VCH-42",
                reason: "Corrected narration"
            )
        )

        let byActor = try repo.list(filter: .init(companyId: tc.companyId, searchText: "reviewer"))
        XCTAssertEqual(byActor.count, 1)

        let byReason = try repo.list(filter: .init(companyId: tc.companyId, searchText: "narration"))
        XCTAssertEqual(byReason.count, 1)

        let byEntity = try repo.list(filter: .init(companyId: tc.companyId, searchText: "vch-42"))
        XCTAssertEqual(byEntity.count, 1)
    }

    func testUnknownAuditActionFailsReadInsteadOfSilentlyFallingBack() throws {
        let tc = try TestCompany.make()
        let now = DateFormatters.formatIsoTimestamp(Date())

        XCTAssertThrowsError(try tc.db.queryOne(
            """
            SELECT ? AS id, ? AS company_id, ? AS timestamp, ? AS actor,
                   ? AS action, ? AS entity_type, ? AS entity_id,
                   NULL AS snapshot_before_json, NULL AS snapshot_after_json, NULL AS reason
            """,
            bind: [
                .text(UUID().uuidString),
                .text(tc.companyId.uuidString),
                .text(now),
                .text("user"),
                .text("totallyUnknownAction"),
                .text("voucher"),
                .text(UUID().uuidString)
            ],
            row: AuditRepository.rowToEvent
        )) { error in
            guard case AppError.database(.rowReadFailed(let message)) = error else {
                return XCTFail("Expected rowReadFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Unknown audit action"))
        }
    }
}
