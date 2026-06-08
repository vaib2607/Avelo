import XCTest
@testable import Avelo

final class AuditRepositoryTests: XCTestCase {

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
