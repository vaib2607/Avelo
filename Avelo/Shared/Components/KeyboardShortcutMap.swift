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
