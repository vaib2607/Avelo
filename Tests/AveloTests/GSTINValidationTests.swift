import XCTest
@testable import Avelo

/// Regression tests for the GSTIN validator. The original implementation
/// checked character classes shifted by one position (expecting a letter
/// first), which rejected every real GSTIN — real ones start with a
/// two-digit state code.
final class GSTINValidationTests: XCTestCase {

    func testAcceptsRealWorldValidGSTINs() {
        // Known-good GSTINs with correct mod-36 check digits.
        XCTAssertTrue(AccountInputValidator.isValidGSTIN("27AAPFU0939F1ZV"))
        XCTAssertTrue(AccountInputValidator.isValidGSTIN("29AAGCB7383J1Z4"))
        XCTAssertTrue(AccountInputValidator.isValidGSTIN("07AAGFF2194N1Z1"))
    }

    func testRejectsWrongCheckDigit() {
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27AAPFU0939F1ZW"))
    }

    func testRejectsUnassignedStateCode() {
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("50AAPFU0939F1ZV"))
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("00AAPFU0939F1ZV"))
    }

    func testRejectsStructuralViolations() {
        XCTAssertFalse(AccountInputValidator.isValidGSTIN(""))
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27AAPFU0939F1Z"))    // 14 chars
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27AAPFU0939F1ZVX"))  // 16 chars
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27AAPFU0939F1YV"))   // 14th char not 'Z'
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27123450939F1ZV"))   // PAN letters missing
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("27AAPFU0939F0ZV"))   // entity code '0'
    }

    func testRejectsOldValidatorsLetterFirstFormat() {
        // The buggy validator would have accepted shapes like this.
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("AABCDE123F1A1B2"))
    }

    func testValidationServicePassthrough() {
        XCTAssertTrue(ValidationService.isValidGSTIN("27AAPFU0939F1ZV"))
        XCTAssertFalse(ValidationService.isValidGSTIN("not-a-gstin"))
    }
}
