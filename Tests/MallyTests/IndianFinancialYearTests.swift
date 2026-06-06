import XCTest
@testable import Mally

final class IndianFinancialYearTests: XCTestCase {

    /// System-timezone gregorian date at noon (DST/offset-robust), matching the
    /// calendar `IndianFinancialYear.fyLabel` uses internally.
    private func localDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
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

    func testDetectReturnsConsistentLabelAndBounds() {
        let fy = IndianFinancialYear.detect(now: localDate(2024, 6, 15))
        XCTAssertEqual(fy.label, "2024-25")
        let start = utcComponents(fy.start)
        let end = utcComponents(fy.end)
        XCTAssertEqual(start.month, 4)
        XCTAssertEqual(end.month, 3)
    }
}
