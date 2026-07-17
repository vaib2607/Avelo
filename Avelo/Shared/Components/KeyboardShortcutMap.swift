import AppKit
import SwiftUI

public enum KeyboardShortcutID: String, CaseIterable, Sendable {
    case kNew, kSave, kCancel, kDelete, kDuplicate
    case kFocusParty, kFocusNarration, kAddLine, kDuplicateLine
    case kSearch, kCommandPalette, kSwitchCompany, kSwitchFY
    case kBackup, kRestore, kToggleSidebar, kPostInventoryLink
}

public struct KeyboardShortcutMap {
    public let id: KeyboardShortcutID
    public let key: KeyEquivalent
    public let modifiers: EventModifiers
    public let label: String

    public init(id: KeyboardShortcutID, key: KeyEquivalent, modifiers: EventModifiers, label: String) {
        self.id = id
        self.key = key
        self.modifiers = modifiers
        self.label = label
    }
}

public enum KeyboardShortcuts {
    public nonisolated(unsafe) static let map: [KeyboardShortcutID: KeyboardShortcutMap] = [
        .kNew:              KeyboardShortcutMap(id: .kNew,              key: "n", modifiers: .command,                  label: "New"),
        .kSave:             KeyboardShortcutMap(id: .kSave,             key: "s", modifiers: .command,                  label: "Save"),
        .kCancel:           KeyboardShortcutMap(id: .kCancel,           key: ".", modifiers: .command,                  label: "Cancel"),
        .kDelete:           KeyboardShortcutMap(id: .kDelete,           key: .delete, modifiers: [],                    label: "Delete"),
        .kDuplicate:        KeyboardShortcutMap(id: .kDuplicate,        key: "d", modifiers: .command,                  label: "Duplicate"),
        .kFocusParty:       KeyboardShortcutMap(id: .kFocusParty,       key: "l", modifiers: .command,                  label: "Focus Party"),
        .kFocusNarration:   KeyboardShortcutMap(id: .kFocusNarration,   key: "i", modifiers: .command,                  label: "Focus Narration"),
        .kAddLine:          KeyboardShortcutMap(id: .kAddLine,          key: .return, modifiers: .command,              label: "Add Line"),
        .kDuplicateLine:    KeyboardShortcutMap(id: .kDuplicateLine,    key: "d", modifiers: [.command, .shift],        label: "Duplicate Line"),
        .kSearch:           KeyboardShortcutMap(id: .kSearch,           key: "f", modifiers: .command,                  label: "Search"),
        .kCommandPalette:   KeyboardShortcutMap(id: .kCommandPalette,   key: "k", modifiers: .command,                  label: "Command Palette"),
        .kSwitchCompany:    KeyboardShortcutMap(id: .kSwitchCompany,    key: "c", modifiers: [.command, .shift],        label: "Switch Company"),
        .kSwitchFY:         KeyboardShortcutMap(id: .kSwitchFY,         key: "y", modifiers: [.command, .shift],        label: "Switch FY"),
        .kBackup:           KeyboardShortcutMap(id: .kBackup,           key: "e", modifiers: [.command, .shift],        label: "Export Backup"),
        .kRestore:          KeyboardShortcutMap(id: .kRestore,          key: "i", modifiers: [.command, .shift],        label: "Open Backup"),
        .kToggleSidebar:    KeyboardShortcutMap(id: .kToggleSidebar,    key: "s", modifiers: [.command, .control],      label: "Toggle Sidebar"),
        .kPostInventoryLink:KeyboardShortcutMap(id: .kPostInventoryLink,key: "p", modifiers: [.command, .shift],        label: "Post Inventory Link")
    ]

    public static func shortcut(for id: KeyboardShortcutID) -> KeyboardShortcutMap? {
        map[id]
    }

    public static func chord(for id: KeyboardShortcutID) -> String {
        guard let s = map[id] else { return "" }
        var parts: [String] = []
        if s.modifiers.contains(.command) { parts.append("⌘") }
        if s.modifiers.contains(.control) { parts.append("⌃") }
        if s.modifiers.contains(.option)  { parts.append("⌥") }
        if s.modifiers.contains(.shift)   { parts.append("⇧") }
        parts.append(s.key.displayString)
        return parts.joined()
    }

    /// Physical-key translation used by the AppKit event monitor. Keeping it
    /// beside the displayed shortcut definitions prevents another private
    /// monitor-owned map from becoming the de facto command source.
    public static func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyboardCommand? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)

        if command && !shift && !option && !control {
            switch keyCode {
            case 18: return .openDashboard
            case 19: return .openVouchers
            case 20: return .openAccounts
            case 21: return .openReports
            case 23: return .openInventory
            case 22: return .openGST
            case 26: return .openPayroll
            case 28: return .openBanking
            case 25: return .openAudit
            case 29: return .openSettings
            case 40: return .commandPalette
            case 44: return .quickSearch
            case 43: return .showShortcutHelp
            default: return nil
            }
        }
        if control && !command && !shift && !option {
            switch keyCode {
            case 100: return .newVoucher(.creditNote)
            case 101: return .newVoucher(.debitNote)
            default: return nil
            }
        }
        guard !command, !shift, !option, !control else { return nil }
        switch keyCode {
        case 53: return .goBack
        case 36, 76: return .drillDown
        case 118: return .newVoucher(.contra)
        case 96: return .newVoucher(.payment)
        case 97: return .newVoucher(.receipt)
        case 98: return .newVoucher(.journal)
        case 100: return .newVoucher(.sales)
        case 101: return .newVoucher(.purchase)
        case 15: return .reload
        default: return nil
        }
    }

    public static func isVoucherSwitch(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard case .newVoucher = command(keyCode: keyCode, modifiers: modifiers) else { return false }
        return true
    }
}

private extension KeyEquivalent {
    var displayString: String {
        switch self {
        case .return:   return "↩"
        case .delete:   return "⌫"
        case .tab:      return "⇥"
        case .escape:   return "⎋"
        case .upArrow:  return "↑"
        case .downArrow:return "↓"
        case .leftArrow:return "←"
        case .rightArrow:return "→"
        default:        return String(self.character)
        }
    }
}
