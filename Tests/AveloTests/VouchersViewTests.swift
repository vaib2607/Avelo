import XCTest
@testable import Avelo

@MainActor
final class VouchersViewTests: XCTestCase {

    func testFilterDateFallbackUsesTodayInsteadOfDistantPast() {
        let fallback = VouchersView.filterDateFallback(nil)
        XCTAssertGreaterThan(fallback.timeIntervalSince1970, 0)
        XCTAssertLessThan(abs(fallback.timeIntervalSinceNow), 5)
    }

    func testFilterDateFallbackPreservesProvidedDate() {
        let date = DateFormatters.parseDate("2024-06-13")!
        XCTAssertEqual(VouchersView.filterDateFallback(date), date)
    }
}
