import AppKit
import XCTest
@testable import Avelo

final class KeyboardShortcutMapTests: XCTestCase {
    func testVoucherFunctionKeyMatrixMatchesTallyAliases() {
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 118, modifiers: []), .newVoucher(.contra))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 96, modifiers: []), .newVoucher(.payment))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 97, modifiers: []), .newVoucher(.receipt))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 98, modifiers: []), .newVoucher(.journal))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 100, modifiers: []), .newVoucher(.sales))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 101, modifiers: []), .newVoucher(.purchase))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 100, modifiers: .control), .newVoucher(.creditNote))
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 101, modifiers: .control), .newVoucher(.debitNote))
    }

    func testModuleAndUtilityAliasesHaveOneTranslationTable() {
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 18, modifiers: .command), .openDashboard)
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 19, modifiers: .command), .openVouchers)
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 40, modifiers: .command), .commandPalette)
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 44, modifiers: .command), .quickSearch)
        XCTAssertEqual(KeyboardShortcuts.command(keyCode: 43, modifiers: .command), .showShortcutHelp)
    }

    func testUnsupportedModifierCombinationsDoNotDispatch() {
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 100, modifiers: [.command, .shift]))
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 36, modifiers: .command))
        XCTAssertFalse(KeyboardShortcuts.isVoucherSwitch(keyCode: 18, modifiers: .command))
    }

    @MainActor
    func testNestedSheetCaptureRemainsActiveUntilEverySheetDismisses() {
        let monitor = KeyboardMonitor()
        monitor.setSheetCapture(true)
        monitor.setSheetCapture(true)
        monitor.setSheetCapture(false)
        XCTAssertTrue(monitor.isCapturingSheet)
        monitor.setSheetCapture(false)
        XCTAssertFalse(monitor.isCapturingSheet)
        monitor.setSheetCapture(false)
        XCTAssertFalse(monitor.isCapturingSheet)
    }
}
