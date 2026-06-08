import SwiftUI

/// Adds `.onAppear`/`.onDisappear` hooks that toggle `KeyboardMonitor.setSheetCapture`.
///
/// Apply to the root of any sheet content so global keyboard shortcuts
/// (F4–F11 voucher keys, etc.) are suppressed while the user is typing in
/// a `TextField` inside the sheet.
public struct SheetKeyboardCapture: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .onAppear    { KeyboardMonitor.shared.setSheetCapture(true) }
            .onDisappear { KeyboardMonitor.shared.setSheetCapture(false) }
    }
}

public extension View {
    /// Suppresses global keyboard shortcuts while this view is on screen.
    func capturesGlobalKeyboard() -> some View {
        modifier(SheetKeyboardCapture())
    }
}
