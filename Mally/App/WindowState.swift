import Foundation
import Combine

@MainActor
public final class WindowState: ObservableObject {

    @Published public var columnVisibility: NavigationSplitViewVisibility = .all
    @Published public var isSidebarShown: Bool = true
    @Published public var selectedLedgerAccountId: Account.ID?
    @Published public var reportSelection: ReportSelection = .trialBalance

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
    case outstanding
    case stockValuation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trialBalance:  return "Trial Balance"
        case .profitLoss:    return "Profit & Loss"
        case .balanceSheet:  return "Balance Sheet"
        case .gstSummary:    return "GST Summary"
        case .dayBook:       return "Day Book"
        case .ledger:        return "Ledger"
        case .outstanding:   return "Outstanding"
        case .stockValuation:return "Stock Valuation"
        }
    }
}
