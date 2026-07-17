import Foundation
import AppKit

/// Translates global NSEvents into `KeyboardCommand`s and dispatches them
/// to the active `KeyboardRouter`.
///
<<<<<<< HEAD
/// Designed for the macOS-only Tally-style UX. Function keys map to voucher
/// types exactly as in Tally: F4 Contra, F5 Payment, F6 Receipt, F7 Journal,
/// F8 Sales, F9 Purchase, Ctrl+F8 Credit Note, Ctrl+F9 Debit Note.
/// Esc/Enter/Cmd-key combinations map to navigation, drill, and
/// quick-search/command-palette commands.
=======
/// Designed for the macOS-only Tally-style UX. Function keys (F4–F11) map to
/// voucher types; Esc/Enter/Cmd-key combinations map to navigation, drill,
/// and quick-search/command-palette commands.
>>>>>>> origin/main
///
/// Key code reference (US keyboard):
///   F1=122, F2=120, F3=99, F4=118, F5=96, F6=97, F7=98, F8=100,
///   F9=101, F10=109, F11=103, F12=111
///   Esc=53, Return=36, Enter=76, Tab=48
///   Cmd+K=40, Cmd+/=44
@MainActor
public final class KeyboardMonitor {

    public static let shared = KeyboardMonitor()

    private var monitor: Any?
    private weak var router: KeyboardRouter?
<<<<<<< HEAD
    private var sheetCaptureDepth: Int = 0
=======
    private var inSheetCapture: Bool = false
>>>>>>> origin/main

    /// Invoked when a voucher function key (F4–F11) is pressed while a sheet is
    /// open and global shortcuts are suppressed, so the UI can show a hint
    /// instead of silently swallowing the key.
    public var onSuppressedKey: (() -> Void)?

    public init() {}

    public func install(router: KeyboardRouter) {
        guard self.monitor == nil else { return }
        self.router = router

        self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
<<<<<<< HEAD
            if self.sheetCaptureDepth > 0 {
=======
            if self.inSheetCapture {
>>>>>>> origin/main
                if self.isVoucherFunctionKey(event) { self.onSuppressedKey?() }
                return event
            }
            if self.handle(event) {
                return nil
            }
            return event
        }
    }

    private func isVoucherFunctionKey(_ event: NSEvent) -> Bool {
<<<<<<< HEAD
        KeyboardShortcuts.isVoucherSwitch(keyCode: event.keyCode, modifiers: event.modifierFlags)
=======
        let mods = event.modifierFlags
        guard !mods.contains(.command), !mods.contains(.shift),
              !mods.contains(.option), !mods.contains(.control) else { return false }
        switch event.keyCode {
        case 118, 96, 97, 98, 100, 101, 109, 103: return true // F4–F11
        default: return false
        }
>>>>>>> origin/main
    }

    public func uninstall() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        self.router = nil
<<<<<<< HEAD
        sheetCaptureDepth = 0
=======
>>>>>>> origin/main
    }

    /// When a sheet/editor is open and wants raw text input, call this to
    /// suppress global shortcuts (so the user can type `F5` inside a text
    /// field without it being intercepted as a Payment voucher shortcut).
    public func setSheetCapture(_ active: Bool) {
<<<<<<< HEAD
        if active {
            sheetCaptureDepth += 1
        } else {
            sheetCaptureDepth = max(0, sheetCaptureDepth - 1)
        }
    }

    var isCapturingSheet: Bool { sheetCaptureDepth > 0 }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let router,
              let command = KeyboardShortcuts.command(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
            return false
        }
        // Native text editing owns unmodified Return/Escape/R. Voucher sheets
        // additionally capture all global commands through `sheetCaptureDepth`.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.window?.firstResponder is NSTextView {
            return false
        }
        router.handle(command)
        return true
=======
        inSheetCapture = active
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let router = router else { return false }
        let keyCode = event.keyCode
        let mods = event.modifierFlags
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        let opt = mods.contains(.option)
        let ctrl = mods.contains(.control)

        if cmd && !shift && !opt && !ctrl {
            switch keyCode {
            case 18: router.handle(.openDashboard); return true   // Cmd+1
            case 19: router.handle(.openAccounts); return true    // Cmd+2
            case 20: router.handle(.openVouchers); return true    // Cmd+3
            case 21: router.handle(.openReports); return true     // Cmd+4
            case 23: router.handle(.openInventory); return true   // Cmd+5
            case 22: router.handle(.openPayroll); return true     // Cmd+6
            case 26: router.handle(.openBanking); return true     // Cmd+7
            case 28: router.handle(.openAudit); return true       // Cmd+8
            case 25: router.handle(.openSettings); return true    // Cmd+9
            case 40: router.handle(.commandPalette); return true  // Cmd+K
            case 44: router.handle(.quickSearch); return true     // Cmd+/
            case 43: router.handle(.showShortcutHelp); return true // Cmd+,
            default: break
            }
        }

        if !cmd && !shift && !opt && !ctrl {
            switch keyCode {
            case 53: router.handle(.goBack); return true                        // Esc
            case 36, 76: router.handle(.drillDown); return true                // Return / numpad Enter
            case 118: router.handle(.newVoucher(.contra)); return true          // F4
            case 96:  router.handle(.newVoucher(.payment)); return true         // F5
            case 97:  router.handle(.newVoucher(.receipt)); return true         // F6
            case 98:  router.handle(.newVoucher(.journal)); return true         // F7
            case 100: router.handle(.newVoucher(.sales)); return true           // F8
            case 101: router.handle(.newVoucher(.purchase)); return true        // F9
            case 109: router.handle(.newVoucher(.creditNote)); return true      // F10
            case 103: router.handle(.newVoucher(.debitNote)); return true       // F11
            case 15: router.handle(.reload); return true                        // R
            default: break
            }
        }

        return false
>>>>>>> origin/main
    }
}
