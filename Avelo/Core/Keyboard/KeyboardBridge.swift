import Foundation
import SwiftUI
import Observation

/// View-side bridge that translates `KeyboardCommand`s into router actions.
///
/// Lives in the SwiftUI environment so any view can observe and react.
@MainActor
@Observable
public final class KeyboardBridge {

    public var lastCommand: KeyboardCommand?
    public var quickSearchActive: Bool = false
    public var commandPaletteActive: Bool = false
    public var shortcutHelpActive: Bool = false

    /// Transient hint shown when a voucher function key is pressed while a
    /// sheet is open. Auto-clears shortly after being set.
    public var suppressedKeyFlash: String?

    private weak var router: AppRouter?
    private var flashGeneration: Int = 0

    public init() {}

    /// Shows a brief hint that voucher shortcuts are unavailable while a sheet
    /// is open, then clears it (unless superseded by a newer flash).
    public func flashSuppressed() {
        flashGeneration &+= 1
        let generation = flashGeneration
        suppressedKeyFlash = "Close this window to switch voucher types."
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let self, self.flashGeneration == generation else { return }
            self.suppressedKeyFlash = nil
        }
    }

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
        case .purchaseOrder: return .newPurchaseOrder
        case .salesOrder:  return .newSalesOrder
        case .receiptNote: return .newReceiptNote
        case .deliveryNote: return .newDeliveryNote
        case .physicalStock: return .newPhysicalStock
        case .stockJournal: return .newStockJournal
        case .rejectionIn:  return .newRejectionIn
        case .rejectionOut: return .newRejectionOut
        case .creditNote:  return .newCreditNote
        case .debitNote:   return .newDebitNote
        case .opening, .payroll:
            return .newJournal
        }
    }
}
