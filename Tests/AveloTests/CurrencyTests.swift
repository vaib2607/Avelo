import XCTest
@testable import Avelo

final class CurrencyTests: XCTestCase {

    func testFormatPaiseIndianGroupingBoundaries() {
        XCTAssertEqual(Currency.formatPaise(0), "₹0.00")
        XCTAssertEqual(Currency.formatPaise(10000), "₹100.00")          // 100 rupees
        XCTAssertEqual(Currency.formatPaise(100000), "₹1,000.00")        // 1,000 rupees
        XCTAssertEqual(Currency.formatPaise(11800000), "₹1,18,000.00")   // PRD canonical grouping
        XCTAssertEqual(Currency.formatPaise(100000000), "₹10,00,000.00") // 10 lakh
        XCTAssertEqual(Currency.formatPaise(12345), "₹123.45")           // paise component preserved
    }

    func testFormatPaiseNegative() {
        XCTAssertEqual(Currency.formatPaise(-10000), "-₹100.00")
        XCTAssertEqual(Currency.formatPaise(-11800000), "-₹1,18,000.00")
    }

    func testFormatPaisePlainStyle() {
        XCTAssertEqual(Currency.formatPaise(11800000, style: .plain), "118000.00")
        XCTAssertEqual(Currency.formatPaise(-12345, style: .plain), "-123.45")
    }

    func testSignedIndianGroupingZeroHasNoSign() {
        XCTAssertEqual(Currency.formatPaise(0, style: .signedIndianGrouping), "₹0.00")
    }

    func testRupeesToPaiseAndBack() {
        let paise = Currency.rupeesToPaise(Decimal(string: "123.45")!)
        XCTAssertEqual(paise, 12345)
        XCTAssertEqual(Currency.paiseToRupees(12345), Decimal(string: "123.45")!)
    }

    func testRupeesToPaiseRoundsToPaise() {
        // 1 paise = 0.01 rupee; sub-paise input must round to nearest paise.
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.014")!), 1001)
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.015")!), 1002)
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.016")!), 1002)
    }

    func testParseRupeeInputRoundTrip() {
        XCTAssertEqual(Currency.parseRupeeInput("1,18,000.00"), 11800000)
        XCTAssertEqual(Currency.parseRupeeInput("100"), 10000)
        XCTAssertEqual(Currency.parseRupeeInput("123.45"), 12345)
    }

    func testParseRupeeInputEdgeCases() {
        XCTAssertEqual(Currency.parseRupeeInput(""), 0)          // empty means zero
        XCTAssertEqual(Currency.parseRupeeInput("   "), 0)        // whitespace trims to empty
        XCTAssertNil(Currency.parseRupeeInput("abc"))            // no digits -> nil
    }

    func testFormatAmountInput() {
        XCTAssertEqual(Currency.formatAmountInput(paise: 0), "0.00")
        XCTAssertEqual(Currency.formatAmountInput(paise: 12345), "123.45")
    }
}
