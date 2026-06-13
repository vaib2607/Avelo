import XCTest
@testable import Avelo

final class Phase6MathRoundingTests: XCTestCase {

    func testPercentagePaiseRoundsHalfUp() {
        XCTAssertEqual(Currency.percentagePaise(1, ratePercent: 50), 1)
        XCTAssertEqual(Currency.percentagePaise(199, ratePercent: 1), 2)
        XCTAssertEqual(Currency.percentagePaise(333, ratePercent: 18), 60)
    }

    func testPercentagePaisePreservesZeroAndNegativeAmounts() {
        XCTAssertEqual(Currency.percentagePaise(0, ratePercent: 18), 0)
        XCTAssertEqual(Currency.percentagePaise(-1000, ratePercent: 18), -180)
    }
}
