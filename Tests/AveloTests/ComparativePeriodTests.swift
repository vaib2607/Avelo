import XCTest
@testable import Avelo

/// AVL-P1-036: pure date-arithmetic and label proof for the comparative
/// period DSL — no report/DB involvement, that's ReportsViewModelTests.
final class ComparativePeriodTests: XCTestCase {

    func testPriorYearShiftsBackOneCalendarYear() {
        let date = DateFormatters.parseDate("2024-06-15")!
        XCTAssertEqual(ComparativePeriod.priorYear.shift(date), DateFormatters.parseDate("2023-06-15")!)
    }

    func testPriorMonthShiftsBackOneMonth() {
        let date = DateFormatters.parseDate("2024-06-15")!
        XCTAssertEqual(ComparativePeriod.priorMonth.shift(date), DateFormatters.parseDate("2024-05-15")!)
    }

    func testPriorQuarterShiftsBackThreeMonths() {
        let date = DateFormatters.parseDate("2024-06-15")!
        XCTAssertEqual(ComparativePeriod.priorQuarter.shift(date), DateFormatters.parseDate("2024-03-15")!)
    }

    func testCustomShiftsBackGivenMonths() {
        let date = DateFormatters.parseDate("2024-06-15")!
        XCTAssertEqual(ComparativePeriod.custom(monthsBack: 5).shift(date), DateFormatters.parseDate("2024-01-15")!)
    }

    func testCustomWithNonPositiveMonthsFallsBackToPriorMonth() {
        let date = DateFormatters.parseDate("2024-06-15")!
        XCTAssertEqual(ComparativePeriod.custom(monthsBack: 0).shift(date), DateFormatters.parseDate("2024-05-15")!)
        XCTAssertEqual(ComparativePeriod.custom(monthsBack: -3).shift(date), DateFormatters.parseDate("2024-05-15")!)
    }

    func testYearBoundaryShiftsAcrossYears() {
        let date = DateFormatters.parseDate("2024-01-15")!
        XCTAssertEqual(ComparativePeriod.priorMonth.shift(date), DateFormatters.parseDate("2023-12-15")!)
        XCTAssertEqual(ComparativePeriod.priorQuarter.shift(date), DateFormatters.parseDate("2023-10-15")!)
    }

    func testColumnLabelsAreDistinctPerMode() {
        XCTAssertEqual(ComparativePeriod.priorYear.columnLabel, "Prior Year (₹)")
        XCTAssertEqual(ComparativePeriod.priorMonth.columnLabel, "Prior Month (₹)")
        XCTAssertEqual(ComparativePeriod.priorQuarter.columnLabel, "Prior Quarter (₹)")
        XCTAssertEqual(ComparativePeriod.custom(monthsBack: 4).columnLabel, "4mo Prior (₹)")
    }
}
