import SwiftUI

public struct RootView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(KeyboardBridge.self) private var keyboardBridge
    @State private var windowState = WindowState()

    public init() {}

    public var body: some View {
        rootContent
    }

    @ViewBuilder
    private var rootContent: some View {
        @Bindable var env = env
        @Bindable var router = router
        @Bindable var keyboardBridge = keyboardBridge
        @Bindable var windowState = windowState

        Group {
            if env.companyContext == nil {
                CompanyPickerView()
            } else {
                VStack(spacing: 0) {
                    ShellContextBar(
                        companyName: env.companyContext?.companyName,
                        financialYearLabel: env.companyContext?.financialYear.label,
                        moduleTitle: router.selection.title,
                        moduleHint: moduleHint(for: router.selection)
                    )
                    NavigationSplitView(columnVisibility: $windowState.columnVisibility) {
                        SidebarView()
                            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
                    } detail: {
                        detailView
                    }
                    .navigationSplitViewStyle(.balanced)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestNewCompany)) { _ in
            router.present(.newCompany)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestOpenCompany)) { _ in
            router.present(.openCompany)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestBackup)) { _ in
            router.present(.backup)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestRestore)) { _ in
            router.present(.restore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestPreferences)) { _ in
            router.present(.preferences)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aveloRequestCloseCompany)) { _ in
            env.closeCompany()
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

    private func moduleHint(for destination: SidebarDestination) -> String {
        switch destination {
        case .dashboard: return "Company overview, live totals, and quick entry."
        case .vouchers:  return "Post, edit, and reverse transactions."
        case .accounts:  return "Groups, ledgers, and master drill-down."
        case .reports:   return "Statements, ledgers, and voucher drill-down."
        case .inventory: return "Stock masters and movement."
        case .gst:       return "GST summary, return prep, and filing views."
        case .payroll:   return "Employees and salary posting."
        case .banking:   return "Statement import and reconciliation."
        case .audit:     return "Append-only history of changes."
        case .settings:  return "Company, FY, backup, restore, and preferences."
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
        case .gst:       GSTView()
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
        case .companyInfo:
            if let ctx = env.companyContext,
               let company = try? CompanyRepository(db: ctx.database).findById(ctx.companyId) {
                CompanyInfoSheet(company: company)
            }
        case .newVoucher, .newJournal, .newPayment, .newReceipt,
             .newContra, .newPurchase, .newSales,
             .newPurchaseOrder, .newSalesOrder, .newReceiptNote, .newDeliveryNote,
             .newPhysicalStock, .newStockJournal, .newRejectionIn, .newRejectionOut,
             .newCreditNote, .newDebitNote:
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
        case .newPurchaseOrder:return .purchaseOrder
        case .newSalesOrder:   return .salesOrder
        case .newReceiptNote:  return .receiptNote
        case .newDeliveryNote: return .deliveryNote
        case .newPhysicalStock:return .physicalStock
        case .newStockJournal: return .stockJournal
        case .newRejectionIn:  return .rejectionIn
        case .newRejectionOut: return .rejectionOut
        case .newCreditNote:   return .creditNote
        case .newDebitNote:    return .debitNote
        default:               return .journal
        }
    }
}
