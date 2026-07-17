import XCTest
@testable import Avelo

final class ReportSelectionTests: XCTestCase {

    func testInventoryDisabledHidesEveryStockReport() {
        let visible = ReportSelection.visibleCases(isInventoryEnabled: false)

        XCTAssertFalse(visible.contains(.stockMovement))
        XCTAssertFalse(visible.contains(.stockRegister))
        XCTAssertFalse(visible.contains(.stockValuation))
        XCTAssertFalse(visible.contains(.stockAgeing))
        XCTAssertTrue(visible.contains(.trialBalance))
        XCTAssertTrue(visible.contains(.cashFlow))
    }

    func testInventoryDisabledFallsBackFromInventoryReportSelection() {
        for selection in ReportSelection.allCases where selection.requiresInventory {
            XCTAssertEqual(
                ReportSelection.permitted(selection, isInventoryEnabled: false),
                .trialBalance
            )
        }
    }

    func testInventoryEnabledKeepsEveryReportSelectionAvailable() {
        XCTAssertEqual(
            ReportSelection.visibleCases(isInventoryEnabled: true),
            ReportSelection.allCases
        )
        XCTAssertEqual(
            ReportSelection.permitted(.stockValuation, isInventoryEnabled: true),
            .stockValuation
        )
    }
}
