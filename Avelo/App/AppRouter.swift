import Foundation
import Observation

@MainActor
@Observable
public final class AppRouter {

    public var selection: SidebarDestination = .dashboard {
        didSet {
            if selection == .inventory && !isInventoryEnabled {
                selection = oldValue == .inventory ? .dashboard : oldValue
            }
        }
    }
    public var presentedSheet: RouterSheet? {
        didSet {
            if presentedSheet?.requiresInventory == true && !isInventoryEnabled {
                presentedSheet = oldValue?.requiresInventory == true ? nil : oldValue
            }
        }
    }
    public var presentedAlert: RouterAlert?

    /// Set when another screen requests the Reports view open a specific
    /// account's ledger. Consumed (and cleared) by `ReportsView`.
    public var pendingLedgerAccountId: Account.ID?
    public var pendingReportSelection: ReportSelection? {
        didSet {
            if pendingReportSelection?.requiresInventory == true && !isInventoryEnabled {
                pendingReportSelection = oldValue?.requiresInventory == true ? nil : oldValue
            }
        }
    }
    public private(set) var featureSet: CompanyFeatureSet = .defaults
    /// Bumped whenever capabilities change or the company context resets.
    /// Views/widgets that cache action availability observe this to discard
    /// stale state instead of each watching individual flags.
    public private(set) var capabilityRevision: Int = 0
    public var isInventoryEnabled: Bool { featureSet.inventory }

    public init() {}

    public func reset() {
        selection = .dashboard
        presentedSheet = nil
        presentedAlert = nil
        pendingLedgerAccountId = nil
        pendingReportSelection = nil
        capabilityRevision &+= 1
    }

    public func go(_ destination: SidebarDestination) {
        guard destination != .inventory || isInventoryEnabled else { return }
        selection = destination
    }

    /// Deep-links to the Reports view showing the given account's ledger.
    public func openLedger(_ accountId: Account.ID) {
        pendingLedgerAccountId = accountId
        selection = .reports
    }

    public func openReport(_ report: ReportSelection) {
        guard !report.requiresInventory || isInventoryEnabled else { return }
        pendingReportSelection = report
        selection = .reports
    }

    public func present(_ sheet: RouterSheet) {
        guard !sheet.requiresInventory || isInventoryEnabled else { return }
        presentedSheet = sheet
    }

    public func setInventoryEnabled(_ enabled: Bool) {
        var updated = featureSet
        updated.inventory = enabled
        setFeatureSet(updated)
    }

    /// Swaps in the new capability set and evicts any route, pending report,
    /// or sheet that a lost capability no longer permits.
    public func setFeatureSet(_ newValue: CompanyFeatureSet) {
        let changed = featureSet != newValue
        featureSet = newValue
        if changed { capabilityRevision &+= 1 }
        if !newValue.inventory {
            if selection == .inventory { selection = .dashboard }
            if pendingReportSelection?.requiresInventory == true { pendingReportSelection = nil }
            if presentedSheet?.requiresInventory == true { presentedSheet = nil }
        }
    }

    public func alert(_ alert: RouterAlert) {
        presentedAlert = alert
    }
}

public enum RouterSheet: Identifiable, Sendable {
    case newCompany
    case openCompany
    case backup
    case restore
    case about
    case preferences
    case companyInfo
    case newVoucher
    case newJournal
    case newPayment
    case newReceipt
    case newContra
    case newPurchase
    case newSales
    case newCreditNote
    case newDebitNote
    case editVoucher(Voucher.ID)
    case reverseVoucher(Voucher.ID)
    case newAccount
    case editAccount(Account.ID)
    case newGroup
    case editGroup(AccountGroup.ID)
    case newFinancialYear
    case newEmployee
    case newItem
    case newCostCentre
    case newCostCategory
    case lockFinancialYear(FinancialYear.ID)
    case closeFinancialYear(FinancialYear.ID)

    public var id: String {
        switch self {
        case .newCompany: return "newCompany"
        case .openCompany: return "openCompany"
        case .backup: return "backup"
        case .restore: return "restore"
        case .about: return "about"
        case .preferences: return "preferences"
        case .companyInfo: return "companyInfo"
        case .newVoucher: return "newVoucher"
        case .newJournal: return "newJournal"
        case .newPayment: return "newPayment"
        case .newReceipt: return "newReceipt"
        case .newContra: return "newContra"
        case .newPurchase: return "newPurchase"
        case .newSales: return "newSales"
        case .newCreditNote: return "newCreditNote"
        case .newDebitNote: return "newDebitNote"
        case .editVoucher(let id): return "editVoucher-\(id.uuidString)"
        case .reverseVoucher(let id): return "reverseVoucher-\(id.uuidString)"
        case .newAccount: return "newAccount"
        case .editAccount(let id): return "editAccount-\(id.uuidString)"
        case .newGroup: return "newGroup"
        case .editGroup(let id): return "editGroup-\(id.uuidString)"
        case .newFinancialYear: return "newFinancialYear"
        case .newEmployee: return "newEmployee"
        case .newItem: return "newItem"
        case .newCostCentre: return "newCostCentre"
        case .newCostCategory: return "newCostCategory"
        case .lockFinancialYear(let id): return "lockFy-\(id.uuidString)"
        case .closeFinancialYear(let id): return "closeFy-\(id.uuidString)"
        }
    }

    public var requiresInventory: Bool {
        switch self {
        case .newItem:
            return true
        default:
            return false
        }
    }
}

public struct RouterAlert: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let confirmLabel: String
    public let cancelLabel: String
    public let destructive: Bool

    public init(title: String, message: String, confirmLabel: String = "OK", cancelLabel: String = "Cancel", destructive: Bool = false) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.destructive = destructive
    }
}
