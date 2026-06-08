import XCTest
@testable import Mally

@MainActor
final class AccountantRCFlowTests: XCTestCase {

    func testLocalAccountantRcFlowStaysUsableEndToEnd() async throws {
        let summary = try await LocalRCFlowRunner.run()
        XCTAssertEqual(summary.companyName, "RC Accountant Co")
        XCTAssertEqual(summary.createdAccountCode, "CUST_RC")
        XCTAssertTrue(summary.trialBalanceBalanced)
        XCTAssertTrue(summary.restoredTrialBalanceBalanced)
    }
}
