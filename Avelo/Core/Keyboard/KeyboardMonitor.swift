import Foundation
import AppKit

/// Translates global NSEvents into `KeyboardCommand`s and dispatches them
/// to the active `KeyboardRouter`.
///
/// Designed for the macOS-only Tally-style UX. Function keys map to voucher
/// types exactly as in Tally: F4 Contra, F5 Payment, F6 Receipt, F7 Journal,
/// F8 Sales, F9 Purchase, Ctrl+F8 Credit Note, Ctrl+F9 Debit Note.
/// Esc/Enter/Cmd-key combinations map to navigation, drill, and
/// quick-search/command-palette commands.
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
    private var sheetCaptureDepth: Int = 0

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
            if self.sheetCaptureDepth > 0 {
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
        KeyboardShortcuts.isVoucherSwitch(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    public func uninstall() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        self.router = nil
        sheetCaptureDepth = 0
    }

    /// When a sheet/editor is open and wants raw text input, call this to
    /// suppress global shortcuts (so the user can type `F5` inside a text
    /// field without it being intercepted as a Payment voucher shortcut).
    public func setSheetCapture(_ active: Bool) {
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
    }
}
