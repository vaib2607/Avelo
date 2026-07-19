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

    func testVoucherEditorScopedChordsAreNotGlobalMonitorCommands() {
        // These keys are deliberately handled by focused SwiftUI controls,
        // never by KeyboardMonitor before native text editing receives them.
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 9, modifiers: .control))   // Ctrl+V
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 15, modifiers: .control))  // Ctrl+R
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 19, modifiers: .option))   // Alt+2
        XCTAssertNil(KeyboardShortcuts.command(keyCode: 36, modifiers: .command))  // Cmd+Return
    }

    func testVoucherShortcutContractIncludesEveryScopedEditorAndTableChord() {
        let keys = Set(VoucherShortcutContract.editorRows.map(\.key)
            + VoucherShortcutContract.tableRows.map(\.key))

        XCTAssertTrue(keys.contains("⌘↩"))
        XCTAssertTrue(keys.contains("Return in Narration"))
        XCTAssertTrue(keys.contains("⌥C in Account picker"))
        XCTAssertTrue(keys.contains("⌃V"))
        XCTAssertTrue(keys.contains("⌃R in Narration"))
        XCTAssertTrue(keys.contains("⌥2"))
        XCTAssertTrue(keys.contains("⌃I"))
        XCTAssertTrue(keys.contains("PgUp / PgDn"))
        XCTAssertEqual(VoucherShortcutContract.editorTitle(for: "⌘↩"), "Post / Save")
        XCTAssertEqual(VoucherShortcutContract.editorTitle(for: "⌃R in Narration"), "Recall narration")
    }

    func testItemModeShortcutRequiresFreshEligibleNonTextEditorContext() {
        XCTAssertTrue(VoucherShortcutContract.canToggleItemInvoice(
            isFreshEligibleDraft: true,
            isEditableTextFocused: false
        ))
        XCTAssertFalse(VoucherShortcutContract.canToggleItemInvoice(
            isFreshEligibleDraft: false,
            isEditableTextFocused: false
        ))
        XCTAssertFalse(VoucherShortcutContract.canToggleItemInvoice(
            isFreshEligibleDraft: true,
            isEditableTextFocused: true
        ))
    }

    /// S9/S11: `VoucherShortcutContract` and `AppActionRegistry` are two
    /// separate shortcut-label sources (editor/table-scoped vs.
    /// menu/toolbar/palette-scoped). Nothing enforces disjointness between
    /// them at compile time, so a shared label here would mean two unrelated
    /// commands display or claim the same chord in help/menu text.
    func testVoucherShortcutContractLabelsDoNotCollideWithRegistryLabels() {
        let contractKeys = Set(VoucherShortcutContract.editorRows.map(\.key)
            + VoucherShortcutContract.tableRows.map(\.key))
        let registryLabels = Set(AppActionRegistry.actions.compactMap(\.shortcutLabel))

        XCTAssertTrue(contractKeys.isDisjoint(with: registryLabels),
                       "Voucher editor/table chords must not collide with registry-driven menu/toolbar/palette chords")
    }

    /// S11: every function-key voucher-create shortcut label the registry
    /// exposes must be unique — two voucher types silently sharing a label
    /// would make the shortcut/help/menu text lie about which voucher opens.
    func testRegistryShortcutLabelsAreUnique() {
        let labels = AppActionRegistry.actions.compactMap(\.shortcutLabel)
        XCTAssertEqual(labels.count, Set(labels).count,
                       "Duplicate shortcutLabel values found in AppActionRegistry.actions: \(labels)")
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
