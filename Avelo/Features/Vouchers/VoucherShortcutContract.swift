import Foundation

/// The user-visible, context-qualified voucher shortcut contract. Registration
/// remains beside the focused control so macOS text editing is never hijacked;
/// help and hints read from this one vocabulary.
enum VoucherShortcutContract {
    static let editorRows: [(key: String, description: String)] = [
        ("⌘↩", "Post or save the active voucher editor"),
        ("Return in Narration", "Insert a newline"),
        ("⌃R in Narration", "Recall a company-scoped narration"),
        ("⌥C in Account picker", "Create an eligible account"),
        ("⌃V", "Toggle item-invoice mode in a new eligible Sales/Purchase voucher"),
        ("⌘Z", "Undo the last line/field change"),
        ("⇧⌘Z", "Redo")
    ]

    static let tableRows: [(key: String, description: String)] = [
        ("⌥2", "Duplicate the selected voucher"),
        ("⌃I", "Create a journal without changing the current list"),
        ("PgUp / PgDn", "Move voucher-table selection")
    ]

    static func canToggleItemInvoice(isFreshEligibleDraft: Bool,
                                     isEditableTextFocused: Bool) -> Bool {
        isFreshEligibleDraft && !isEditableTextFocused
    }

    /// Cmd+Z/Shift+Cmd+Z at the ViewModel level (line add/remove, committed
    /// field values) must never fire while a text field is mid-edit — native
    /// NSTextField/TextEditor already handle plain-text Cmd+Z internally for
    /// in-progress character-level edits, and stealing that would break the
    /// platform-native behavior users expect.
    static func canUndoRedo(isEditableTextFocused: Bool) -> Bool {
        !isEditableTextFocused
    }

    static func editorTitle(for key: String) -> String {
        switch key {
        case "⌘↩": return "Post / Save"
        case "⌃R in Narration": return "Recall narration"
        case "⌥C in Account picker": return "Create account"
        case "⌃V": return "Toggle item invoice"
        case "⌘Z": return "Undo"
        case "⇧⌘Z": return "Redo"
        default: return editorRows.first(where: { $0.key == key })?.description ?? key
        }
    }
}
