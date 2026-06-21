import XCTest
@testable import Avelo

final class FinancialYearServiceTests: XCTestCase {

    func testCloseFinancialYearConfirmationCancelAbortsWithoutStateChange() throws {
        var confirmation = CloseFinancialYearConfirmationState()
        let closed = false

        confirmation.requestClose()
        XCTAssertTrue(confirmation.isPresented)

        confirmation.cancel()

        XCTAssertFalse(confirmation.isPresented)
        XCTAssertFalse(closed)
    }

    func testCloseFinancialYearConfirmationConfirmProceeds() throws {
        var confirmation = CloseFinancialYearConfirmationState()
        var closed = false

        confirmation.requestClose()
        confirmation.confirm {
            closed = true
        }

        XCTAssertFalse(confirmation.isPresented)
        XCTAssertTrue(closed)
    }

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

    func testFindOpenForCompanyExcludesClosedYears() throws {
        let tc = try TestCompany.make()
        let repo = FinancialYearRepository(db: tc.db)
        let openFY = try repo.findOpenForCompany(tc.companyId)
        XCTAssertEqual(openFY.count, 1)

        let closedFY = FinancialYear(
            companyId: tc.companyId,
            label: "2023-24",
            startDate: DateFormatters.parseDate("2023-04-01")!,
            endDate: DateFormatters.parseDate("2024-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2023-04-01")!,
            isLocked: true,
            isClosed: true
        )
        try repo.insert(closedFY)

        let refreshed = try repo.findOpenForCompany(tc.companyId)
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed.first?.id, tc.fy.id)
    }
}
