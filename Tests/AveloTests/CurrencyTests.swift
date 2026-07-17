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

<<<<<<< HEAD
    func testFormatPaiseHandlesInt64MinWithoutTrapping() {
        XCTAssertEqual(Currency.formatPaise(Int64.min), "-₹92,23,37,20,36,85,47,758.08")
    }

    func testRupeesToPaiseAndBack() throws {
        let paise = try Currency.rupeesToPaise(Decimal(string: "123.45")!)
=======
    func testRupeesToPaiseAndBack() {
        let paise = Currency.rupeesToPaise(Decimal(string: "123.45")!)
>>>>>>> origin/main
        XCTAssertEqual(paise, 12345)
        XCTAssertEqual(Currency.paiseToRupees(12345), Decimal(string: "123.45")!)
    }

<<<<<<< HEAD
    func testRupeesToPaiseRoundsToPaise() throws {
        // 1 paise = 0.01 rupee; sub-paise input must round to nearest paise.
        XCTAssertEqual(try Currency.rupeesToPaise(Decimal(string: "10.014")!), 1001)
        XCTAssertEqual(try Currency.rupeesToPaise(Decimal(string: "10.015")!), 1002)
        XCTAssertEqual(try Currency.rupeesToPaise(Decimal(string: "10.016")!), 1002)
    }

    func testRupeesToPaiseThrowsOnOverflow() {
        XCTAssertThrowsError(try Currency.rupeesToPaise(Decimal(string: "999999999999999999999")!)) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule overflow, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
        }
=======
    func testRupeesToPaiseRoundsToPaise() {
        // 1 paise = 0.01 rupee; sub-paise input must round to nearest paise.
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.014")!), 1001)
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.015")!), 1002)
        XCTAssertEqual(Currency.rupeesToPaise(Decimal(string: "10.016")!), 1002)
>>>>>>> origin/main
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

<<<<<<< HEAD
    // AVL-P0-021: locale-aware decimal parsing. Indian-typed amounts always
    // round-trip; comma-decimal paste sources (European locale, spreadsheet
    // exports) resolve to the same paise instead of being silently scaled by
    // 100x/1000x; genuinely ambiguous or malformed shapes fail closed (nil)
    // rather than Decimal's lenient "parse a valid prefix" behavior.

    func testParseRupeeInputIndianGroupingConventions() {
        XCTAssertEqual(Currency.parseRupeeInput("1,234"), 123400)       // single comma, 3 digits after -> grouping
        XCTAssertEqual(Currency.parseRupeeInput("1,18,000"), 11800000) // repeated commas -> grouping
        XCTAssertEqual(Currency.parseRupeeInput("1,18,000.50"), 11800050)
    }

    func testParseRupeeInputCommaDecimalLocale() {
        XCTAssertEqual(Currency.parseRupeeInput("1234,50"), 123450)  // single comma, 2 digits -> decimal
        XCTAssertEqual(Currency.parseRupeeInput("12,5"), 1250)       // single comma, 1 digit -> decimal
    }

    func testParseRupeeInputEuropeanThousandsAndDecimal() {
        // European paste: "." groups, "," is the decimal point.
        XCTAssertEqual(Currency.parseRupeeInput("1.234,56"), 123456)
        XCTAssertEqual(Currency.parseRupeeInput("1.18.000,00"), 11800000)
    }

    func testParseRupeeInputRejectsMalformedShapesInsteadOfTruncating() {
        XCTAssertNil(Currency.parseRupeeInput("12.34.56"))  // repeated "." is never valid grouping
        XCTAssertNil(Currency.parseRupeeInput(".."))
        XCTAssertNil(Currency.parseRupeeInput(","))
        XCTAssertNil(Currency.parseRupeeInput("12."))       // trailing separator, no digits after
        XCTAssertNil(Currency.parseRupeeInput("12.345"))    // single "." with 3 digits is ambiguous, not grouping
        XCTAssertNil(Currency.parseRupeeInput("12,3456"))   // single "," with 4+ digits is neither shape
    }

=======
>>>>>>> origin/main
    func testFormatAmountInput() {
        XCTAssertEqual(Currency.formatAmountInput(paise: 0), "0.00")
        XCTAssertEqual(Currency.formatAmountInput(paise: 12345), "123.45")
    }
}
