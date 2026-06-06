import Foundation
import SwiftUI

/// View-side bridge that translates `KeyboardCommand`s into router actions.
///
/// Lives in the SwiftUI environment so any view can observe and react.
@MainActor
public final class KeyboardBridge: ObservableObject {

    @Published public var lastCommand: KeyboardCommand?
    @Published public var quickSearchActive: Bool = false
    @Published public var commandPaletteActive: Bool = false
    @Published public var shortcutHelpActive: Bool = false

    private weak var router: AppRouter?

    public init() {}

    public func attach(router: AppRouter) {
        self.router = router
    }

    public func dispatch(_ command: KeyboardCommand) {
        lastCommand = command
        switch command {
        case .openDashboard:     router?.go(.dashboard)
        case .openAccounts:      router?.go(.accounts)
        case .openVouchers:      router?.go(.vouchers)
        case .openReports:       router?.go(.reports)
        case .openInventory:     router?.go(.inventory)
        case .openPayroll:       router?.go(.payroll)
        case .openBanking:       router?.go(.banking)
        case .openAudit:         router?.go(.audit)
        case .openSettings:      router?.go(.settings)

        case .newVoucher(let type):
            router?.present(sheet(for: type))

        case .newAccount:        router?.present(.newAccount)
        case .newItem:           router?.present(.newItem)
        case .newEmployee:       router?.present(.newEmployee)

        case .commandPalette:    commandPaletteActive = true
        case .quickSearch:       quickSearchActive = true
        case .showShortcutHelp:  shortcutHelpActive = true
        case .goBack, .drillDown, .reload, .unknownSequence:
            break
        }
    }

    public func dismissCommandPalette() { commandPaletteActive = false }
    public func dismissQuickSearch()    { quickSearchActive = false }
    public func dismissShortcutHelp()   { shortcutHelpActive = false }

    private func sheet(for type: VoucherType.Code) -> RouterSheet {
        switch type {
        case .journal:     return .newJournal
        case .payment:     return .newPayment
        case .receipt:     return .newReceipt
        case .contra:      return .newContra
        case .purchase:    return .newPurchase
        case .sales:       return .newSales
        case .creditNote:  return .newCreditNote
        case .debitNote:   return .newDebitNote
        case .opening, .payroll:
            return .newJournal
        }
    }
}
