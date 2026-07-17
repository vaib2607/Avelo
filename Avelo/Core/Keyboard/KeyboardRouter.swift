import Foundation
import AppKit
import Observation

public enum KeyboardCommand: Sendable, Equatable {
    case openDashboard
    case openAccounts
    case openVouchers
    case openReports
    case openInventory
<<<<<<< HEAD
    case openGST
=======
>>>>>>> origin/main
    case openPayroll
    case openBanking
    case openAudit
    case openSettings

    case newVoucher(VoucherType.Code)
    case newAccount
    case newItem
    case newEmployee

    case goBack
    case drillDown
    case reload

    case quickSearch
    case commandPalette
    case showShortcutHelp

    case unknownSequence(String)
}

public enum KeyboardContext: Equatable, Sendable {
    case idle
    case voucherEdit
    case accountDrill(Account.ID)
    case search

    public static func == (lhs: KeyboardContext, rhs: KeyboardContext) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.voucherEdit, .voucherEdit), (.search, .search):
            return true
        case (.accountDrill(let a), .accountDrill(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
@Observable
public final class KeyboardRouter {

    public private(set) var context: KeyboardContext = .idle
    public private(set) var pendingBuffer: String = ""
    public var lastCommand: KeyboardCommand?

    public var onCommand: ((KeyboardCommand) -> Void)?

    public init() {}

    public func reset() {
        context = .idle
        pendingBuffer = ""
    }

    public func enter(_ context: KeyboardContext) {
        self.context = context
    }

    public func handle(_ command: KeyboardCommand) {
        lastCommand = command
        onCommand?(command)
    }

    public func appendBuffer(_ s: String) {
        pendingBuffer += s
    }

    public func clearBuffer() {
        pendingBuffer = ""
    }
}
