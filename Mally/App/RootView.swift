import SwiftUI

public struct RootView: View {

    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var windowState = WindowState()

    public init() {}

    public var body: some View {
        Group {
            if env.companyContext == nil {
                CompanyPickerView()
            } else {
                NavigationSplitView(columnVisibility: $windowState.columnVisibility) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
                } detail: {
                    detailView
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .environmentObject(windowState)
        .overlay(alignment: .top) {
            ErrorBannerHost()
        }
        .task { await env.bootstrap() }
        .alert(item: $env.globalError) { err in
            Alert(title: Text("Error"),
                  message: Text(err.userMessage),
                  dismissButton: .default(Text("OK")) { env.globalError = nil })
        }
        .onReceive(NotificationCenter.default.publisher(for: .mallyRequestNewCompany)) { _ in
            env.router.present(.newCompany)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mallyRequestBackup)) { _ in
            env.router.present(.backup)
        }
        .sheet(item: $env.router.presentedSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch env.router.selection {
        case .dashboard: DashboardView()
        case .vouchers:  VouchersView()
        case .accounts:  AccountsView()
        case .reports:   ReportsView()
        case .inventory: InventoryView()
        case .payroll:   PayrollView()
        case .banking:   BankingView()
        case .audit:     AuditView()
        case .settings:  SettingsView()
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: RouterSheet) -> some View {
        switch sheet {
        case .newCompany:           NewCompanySheet()
        case .openCompany:          OpenCompanySheet()
        case .backup:               BackupSheet()
        case .restore:              RestoreSheet()
        case .about:                AboutSheet()
        case .preferences:          PreferencesSheet()
        case .newVoucher, .newJournal, .newPayment, .newReceipt,
             .newContra, .newPurchase, .newSales, .newCreditNote, .newDebitNote:
            NewVoucherSheet(initialType: sheet.initialVoucherType)
        case .editVoucher(let id):  EditVoucherSheet(voucherId: id)
        case .reverseVoucher(let id): ReverseVoucherSheet(voucherId: id)
        case .newAccount:           NewAccountSheet()
        case .newFinancialYear:     NewFinancialYearSheet()
        case .newEmployee:          NewEmployeeSheet()
        case .newItem:              NewItemSheet()
        case .lockFinancialYear(let id): LockFinancialYearSheet(fyId: id)
        case .closeFinancialYear(let id): CloseFinancialYearSheet(fyId: id)
        case .manageInventory:      ManageInventorySheet()
        case .managePayroll:        ManagePayrollSheet()
        }
    }
}

extension RouterSheet {
    var initialVoucherType: VoucherType.Code {
        switch self {
        case .newVoucher:      return .journal
        case .newJournal:      return .journal
        case .newPayment:      return .payment
        case .newReceipt:      return .receipt
        case .newContra:       return .contra
        case .newPurchase:     return .purchase
        case .newSales:        return .sales
        case .newCreditNote:   return .creditNote
        case .newDebitNote:    return .debitNote
        default:               return .journal
        }
    }
}
