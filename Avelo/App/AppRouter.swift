import Foundation
import Observation

@MainActor
@Observable
public final class AppRouter {

    public var selection: SidebarDestination = .dashboard
    public var presentedSheet: RouterSheet?
    public var presentedAlert: RouterAlert?

    /// Set when another screen requests the Reports view open a specific
    /// account's ledger. Consumed (and cleared) by `ReportsView`.
    public var pendingLedgerAccountId: Account.ID?
    public var pendingReportSelection: ReportSelection?

    public init() {}

    public func reset() {
        selection = .dashboard
        presentedSheet = nil
        presentedAlert = nil
        pendingLedgerAccountId = nil
        pendingReportSelection = nil
    }

    public func go(_ destination: SidebarDestination) {
        selection = destination
    }

    /// Deep-links to the Reports view showing the given account's ledger.
    public func openLedger(_ accountId: Account.ID) {
        pendingLedgerAccountId = accountId
        selection = .reports
    }

    public func openReport(_ report: ReportSelection) {
        pendingReportSelection = report
        selection = .reports
    }

    public func present(_ sheet: RouterSheet) {
        presentedSheet = sheet
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
    case newFinancialYear
    case newEmployee
    case newItem
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
        case .newFinancialYear: return "newFinancialYear"
        case .newEmployee: return "newEmployee"
        case .newItem: return "newItem"
        case .lockFinancialYear(let id): return "lockFy-\(id.uuidString)"
        case .closeFinancialYear(let id): return "closeFy-\(id.uuidString)"
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
