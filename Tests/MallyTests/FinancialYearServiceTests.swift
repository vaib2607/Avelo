import XCTest
@testable import Mally

final class FinancialYearServiceTests: XCTestCase {

    func testLockWritesAuditEvent() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)

        try service.lock(tc.fy.id, reason: "period close")

        let events = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .financialYearLocked)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.entityId, tc.fy.id.uuidString)
        XCTAssertEqual(events.first?.reason, "period close")
    }
}
