import XCTest
@testable import Avelo

final class IndianFinancialYearTests: XCTestCase {

    /// UTC-anchored date at noon, matching the fixed reference frame
    /// `IndianFinancialYear` uses internally (AVL-P0-023: FY detection must
    /// not depend on the device's ambient system timezone). Building this
    /// with an explicit UTC calendar, rather than the previous
    /// `Calendar(identifier: .gregorian)` default (ambient timezone), keeps
    /// these tests deterministic regardless of which timezone CI runs in.
    private func localDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private func utcComponents(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year, .month, .day], from: date)
    }

    func testFyLabelOnOrAfterApril() {
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2024, 4, 1)), "2024-25")
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2024, 6, 15)), "2024-25")
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2024, 12, 31)), "2024-25")
    }

    func testFyLabelBeforeApril() {
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2025, 1, 1)), "2024-25")
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2025, 3, 31)), "2024-25")
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: localDate(2024, 2, 15)), "2023-24")
    }

    func testStartDateIsAprilFirst() {
        let comps = utcComponents(IndianFinancialYear.startDate(ofFYStartingYear: 2024))
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1)
    }

    func testEndDateIsMarchThirtyFirstNextYear() {
        let comps = utcComponents(IndianFinancialYear.endDate(ofFYStartingYear: 2024))
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 31)
    }

    func testStartYearFromLabel() {
        XCTAssertEqual(IndianFinancialYear.startYear(fromLabel: "2024-25"), 2024)
        XCTAssertNil(IndianFinancialYear.startYear(fromLabel: "garbage"))
    }

    /// AVL-P0-023 regression: FY detection is anchored to a fixed UTC
    /// reference frame, not the device's ambient system timezone. Before the
    /// fix, `fyLabel`/`start`/`end` extracted year/month using
    /// `Calendar(identifier: .gregorian)` with no explicit timezone, which
    /// defaults to `TimeZone.current` -- so the very same instant could
    /// resolve to a different (and wrong) financial year purely because a
    /// user's Mac was set to a different system timezone near a month
    /// boundary. `startDate`/`endDate` already built FY boundaries against
    /// explicit UTC, so this also fixes an internal inconsistency between
    /// the two halves of this type.
    func testFyLabelIsIndependentOfAmbientTimezoneAtMonthBoundary() {
        var c = DateComponents()
        c.year = 2024; c.month = 4; c.day = 1; c.hour = 0; c.minute = 30
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let justAfterMidnightApril1UTC = utc.date(from: c)!

        // A device set to a timezone behind UTC (e.g. US Pacific, UTC-7/-8)
        // would still read this instant as March 31 in local wall-clock time.
        // FY detection must not follow that local reading.
        XCTAssertEqual(IndianFinancialYear.fyLabel(for: justAfterMidnightApril1UTC), "2024-25")
        XCTAssertEqual(utc.component(.month, from: IndianFinancialYear.start(for: justAfterMidnightApril1UTC)), 4)
    }

    func testDetectReturnsConsistentLabelAndBounds() {
        let fy = IndianFinancialYear.detect(now: localDate(2024, 6, 15))
        XCTAssertEqual(fy.label, "2024-25")
        let start = utcComponents(fy.start)
        let end = utcComponents(fy.end)
        XCTAssertEqual(start.month, 4)
        XCTAssertEqual(end.month, 3)
    }
}
