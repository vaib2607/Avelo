import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
public final class WindowState {

    public var columnVisibility: NavigationSplitViewVisibility = .all
    public var isSidebarShown: Bool = true
    public var selectedLedgerAccountId: Account.ID?
    public var reportSelection: ReportSelection = .trialBalance

    public init() {}

    public func toggleSidebar() {
        isSidebarShown.toggle()
        columnVisibility = isSidebarShown ? .all : .detailOnly
    }
}

public enum ReportSelection: String, CaseIterable, Identifiable, Sendable {
    case trialBalance
    case profitLoss
    case balanceSheet
    case gstSummary
    case dayBook
    case ledger
    case cashBook
    case bankBook
    case receivables
    case payables
    case stockMovement
    case stockRegister
    case gstFiling
    case outstanding
    case stockValuation
    case cashFlow
    case stockAgeing

    public var id: String { rawValue }

    /// Inventory reports are unavailable when the active company has disabled
    /// the Inventory capability. Keeping this classification on the selection
    /// type lets every navigation surface apply the same capability boundary.
    public var requiresInventory: Bool {
        switch self {
        case .stockMovement, .stockRegister, .stockValuation, .stockAgeing:
            return true
        default:
            return false
        }
    }

    public static func visibleCases(isInventoryEnabled: Bool) -> [ReportSelection] {
        isInventoryEnabled ? allCases : allCases.filter { !$0.requiresInventory }
    }

    public static func permitted(
        _ selection: ReportSelection,
        isInventoryEnabled: Bool
    ) -> ReportSelection {
        selection.requiresInventory && !isInventoryEnabled ? .trialBalance : selection
    }

    public var title: String {
        switch self {
        case .trialBalance:  return "Trial Balance"
        case .profitLoss:    return "Profit & Loss"
        case .balanceSheet:  return "Balance Sheet"
        case .gstSummary:    return "GST Summary"
        case .dayBook:       return "Day Book"
        case .ledger:        return "Ledger"
        case .cashBook:      return "Cash Book"
        case .bankBook:      return "Bank Book"
        case .receivables:   return "Receivables"
        case .payables:      return "Payables"
        case .stockMovement: return "Stock Movement"
        case .stockRegister: return "Stock Register"
        case .gstFiling:     return "GST Filing Views"
        case .outstanding:   return "Outstanding"
        case .stockValuation:return "Stock Summary"
        case .cashFlow:      return "Cash Flow"
        case .stockAgeing:   return "Stock Ageing"
        }
    }
}
