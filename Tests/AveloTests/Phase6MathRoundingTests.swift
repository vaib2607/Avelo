import XCTest
@testable import Avelo

final class Phase6MathRoundingTests: XCTestCase {

    func testPercentagePaiseRoundsHalfUp() throws {
        XCTAssertEqual(try Currency.percentagePaise(1, ratePercent: 50), 1)
        XCTAssertEqual(try Currency.percentagePaise(199, ratePercent: 1), 2)
        XCTAssertEqual(try Currency.percentagePaise(333, ratePercent: 18), 60)
    }

    func testPercentagePaisePreservesZeroAndNegativeAmounts() throws {
        XCTAssertEqual(try Currency.percentagePaise(0, ratePercent: 18), 0)
        XCTAssertEqual(try Currency.percentagePaise(-1000, ratePercent: 18), -180)
    }

    func testPercentagePaiseThrowsOnOverflow() {
        XCTAssertThrowsError(try Currency.percentagePaise(Int64.max, ratePercent: 100)) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule overflow, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
        }
    }
}
