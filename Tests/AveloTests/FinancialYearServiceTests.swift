import XCTest
@testable import Avelo

final class FinancialYearServiceTests: XCTestCase {

<<<<<<< HEAD
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

=======
>>>>>>> origin/main
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
<<<<<<< HEAD
        XCTAssertNotNil(events.first?.snapshotBeforeJson)
        XCTAssertNotNil(events.first?.snapshotAfterJson)
    }

    func testUnlockWritesExactlyOneDedicatedAuditEvent() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)
        try service.lock(tc.fy.id, reason: "period close")

        try service.unlock(tc.fy.id, reason: "approved correction")

        let events = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .financialYearUnlocked)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.entityId, tc.fy.id.uuidString)
        XCTAssertEqual(events.first?.reason, "approved correction")
        XCTAssertNotNil(events.first?.snapshotBeforeJson)
        XCTAssertNotNil(events.first?.snapshotAfterJson)
    }

    func testUnlockRollsBackWhenAuditInsertFails() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)
        try service.lock(tc.fy.id, reason: "period close")
        try tc.db.execute(
            "CREATE TRIGGER test_reject_unlock_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'financialYearUnlocked' BEGIN SELECT RAISE(ABORT, 'test audit failure'); END;"
        )

        XCTAssertThrowsError(try service.unlock(tc.fy.id, reason: "must roll back"))

        XCTAssertEqual(try FinancialYearRepository(db: tc.db).findById(tc.fy.id)?.isLocked, true)
        XCTAssertEqual(
            try AuditRepository(db: tc.db).list(filter: .init(companyId: tc.companyId, action: .financialYearUnlocked)).count,
            0
        )
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

    func testCreateRejectsOverlappingFinancialYear() throws {
        let tc = try TestCompany.make()
        let service = FinancialYearService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(
            try service.create(
                label: "2024-25 overlap",
                startDate: DateFormatters.parseDate("2024-10-01")!,
                endDate: DateFormatters.parseDate("2025-09-30")!,
                booksBeginDate: DateFormatters.parseDate("2024-10-01")!
            )
        ) { error in
            guard case AppError.validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .financialYearOverlap)
        }
    }

    func testFinancialYearLookupReturnsSingleAdjacentMatch() throws {
        let tc = try TestCompany.make()
        let repo = FinancialYearRepository(db: tc.db)
        let nextYear = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try repo.insert(nextYear)

        let checker = FiscalLockChecker(db: tc.db)
        let boundaryMatch = try checker.financialYear(
            containing: DateFormatters.parseDate("2025-04-01")!,
            companyId: tc.companyId
        )
        XCTAssertEqual(boundaryMatch, nextYear.id)
    }

    func testFinancialYearLookupFailsClosedWhenCorruptYearsOverlap() throws {
        let tc = try TestCompany.make()
        let now = DateFormatters.formatIsoTimestamp(Date())

        try tc.db.execute("DROP TRIGGER IF EXISTS trg_avelo_fy_no_overlap")
        try tc.db.execute("DROP TRIGGER IF EXISTS trg_avelo_fy_no_overlap_update")

        try tc.db.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(UUID().uuidString),
                .text(tc.companyId.uuidString),
                .text("Corrupt Overlap"),
                .date(DateFormatters.parseDate("2024-10-01")!),
                .date(DateFormatters.parseDate("2025-09-30")!),
                .date(DateFormatters.parseDate("2024-10-01")!),
                .text(now)
            ]
        )

        XCTAssertThrowsError(
            try FiscalLockChecker(db: tc.db).financialYear(
                containing: DateFormatters.parseDate("2024-12-01")!,
                companyId: tc.companyId
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule failure, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overlapping financial years"))
        }
=======
>>>>>>> origin/main
    }
}
