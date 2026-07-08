import XCTest
@testable import Avelo

final class AccountInputValidatorGSTINTests: XCTestCase {

    func testValidGSTINIsAccepted() {
        XCTAssertTrue(AccountInputValidator.isValidGSTIN("27ABCDE1234F1Z5"))
    }

    func testInvalidGSTINIsRejected() {
        XCTAssertFalse(AccountInputValidator.isValidGSTIN("ABCDE1234FZZZ12"))
    }
}
