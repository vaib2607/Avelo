import XCTest
@testable import Avelo

/// AVL-P0-022: place-of-supply is derived from a GSTIN's leading two-digit
/// state code rather than needing a separate address/state field on Account.
final class GSTStateCodeTests: XCTestCase {

    func testStateNameForKnownPrefixes() {
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "27ABCDE1234F1Z5"), "Maharashtra")
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "07ABCDE1234F1Z5"), "Delhi")
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "29ABCDE1234F1Z5"), "Karnataka")
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "33ABCDE1234F1Z5"), "Tamil Nadu")
    }

    func testStateNameReturnsNilForUnknownOrMalformedInput() {
        XCTAssertNil(GSTStateCode.stateName(forGSTIN: "50ABCDE1234F1Z5")) // unassigned prefix
        XCTAssertNil(GSTStateCode.stateName(forGSTIN: "2")) // too short
        XCTAssertNil(GSTStateCode.stateName(forGSTIN: ""))
    }

    func testStateNameForSpecialJurisdictionCodes() {
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "97ABCDE1234F1Z5"), "Other Territory")
        XCTAssertEqual(GSTStateCode.stateName(forGSTIN: "99ABCDE1234F1Z5"), "Centre Jurisdiction")
    }
}
