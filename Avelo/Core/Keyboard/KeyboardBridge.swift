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
    private var isInventoryEnabledProvider: () -> Bool = { false }
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

    /// AVL-P0-033: Inventory shortcuts must no-op (not route through a
    /// screen that no longer appears anywhere else) when disabled. A
    /// closure rather than a stored `AppEnvironment` reference keeps this
    /// class testable without constructing a full environment/company.
    public func attach(isInventoryEnabled: @escaping () -> Bool) {
        self.isInventoryEnabledProvider = isInventoryEnabled
    }

    private var isInventoryEnabled: Bool { isInventoryEnabledProvider() }

    public func dispatch(_ command: KeyboardCommand) {
        lastCommand = command
        switch command {
        case .openDashboard:     router?.go(.dashboard)
        case .openAccounts:      performRegistryAction(.accountsDisplay)
        case .openVouchers:      performRegistryAction(.vouchersDisplay)
        case .openReports:       router?.go(.reports)
        case .openInventory:
            router?.setInventoryEnabled(isInventoryEnabled)
            if isInventoryEnabled { router?.go(.inventory) }
        case .openGST:           router?.go(.gst)
        case .openPayroll:       router?.go(.payroll)
        case .openBanking:       router?.go(.banking)
        case .openAudit:         router?.go(.audit)
        case .openSettings:      router?.go(.settings)

        case .newVoucher(let type):
            performRegistryAction(voucherCreateActionId(for: type))

        case .newAccount:        performRegistryAction(.accountCreate)
        case .newItem:
            router?.setInventoryEnabled(isInventoryEnabled)
            if isInventoryEnabled { router?.present(.newItem) }
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

    private func performRegistryAction(_ id: AppActionID) {
        guard let router else { return }
        AppActionRegistry.perform(id, router: router)
    }

    /// `.opening`/`.payroll` have no "New X" sheet in the registry (nothing
    /// dispatches them today — no keycode maps to those types — but this
    /// keeps the old `sheet(for:)` fallback to Journal exact if that ever changes).
    private func voucherCreateActionId(for type: VoucherType.Code) -> AppActionID {
        switch type {
        case .opening, .payroll: return .voucherCreate(.journal)
        default: return .voucherCreate(type)
        }
    }
}
