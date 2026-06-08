import SwiftUI

public struct RootView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(KeyboardBridge.self) private var keyboardBridge
    @State private var windowState = WindowState()

    public init() {}

    public var body: some View {
        @Bindable var env = env
        @Bindable var router = router
        @Bindable var keyboardBridge = keyboardBridge
        @Bindable var windowState = windowState

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
        .environment(windowState)
        .overlay(alignment: .top) {
            ErrorBannerHost()
        }
        .overlay(alignment: .bottom) {
            if let flash = keyboardBridge.suppressedKeyFlash {
                Label(flash, systemImage: "keyboard.badge.ellipsis")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardBridge.suppressedKeyFlash)
        .task {
            await env.bootstrap()
            keyboardBridge.attach(router: router)
        }
        .alert(item: Binding(
            get: { env.globalError },
            set: { env.globalError = $0 }
        )) { err in
            Alert(title: Text("Error"),
                  message: Text(err.localizedMessage),
                  dismissButton: .default(Text("OK")) { env.globalError = nil })
        }
        .onReceive(NotificationCenter.default.publisher(for: .mallyRequestNewCompany)) { _ in
            router.present(.newCompany)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mallyRequestBackup)) { _ in
            router.present(.backup)
        }
        .sheet(item: env.presentedSheetBinding) { sheet in
            sheetView(for: sheet)
                .capturesGlobalKeyboard()
        }
        .sheet(isPresented: $keyboardBridge.shortcutHelpActive) {
            ShortcutHelpSheet()
                .capturesGlobalKeyboard()
        }
        .sheet(isPresented: $keyboardBridge.commandPaletteActive) {
            CommandPaletteSheet()
                .capturesGlobalKeyboard()
        }
        .sheet(isPresented: $keyboardBridge.quickSearchActive) {
            QuickSearchSheet()
                .capturesGlobalKeyboard()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch router.selection {
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
        case .editAccount(let id):  NewAccountSheet(existing: id)
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
