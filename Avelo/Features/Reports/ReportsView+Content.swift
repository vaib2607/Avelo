import SwiftUI

@MainActor
struct ReportsContent: View {
    let vm: ReportsViewModel?

    var body: some View {
        if let vm {
            ReportsBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
struct ReportsBody: View {
    @Environment(AppEnvironment.self) var env
    @Bindable var vm: ReportsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Reports",
                subtitle: "Trial balance, ledgers, statements, and drill-down views built for quick review.",
                hints: [
                    .init(title: "Trial balance", key: "⌘1"),
                    .init(title: "Ledger", key: "⌘6"),
                    .init(title: "Refresh", key: "⌘R")
                ]
            )
            Text("Reports > \(vm.selection.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            if let error = vm.error, vm.selection != .balanceSheet {
                Text(error.localizedMessage)
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            HSplitView {
                sidebar
                    .frame(minWidth: 220)
                main
                    .frame(minWidth: 540)
            }
        }
        .onChange(of: vm.selection) { _, _ in vm.reload() }
        .safeAreaInset(edge: .bottom) {
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Select a report on the left, then drill into account or voucher rows."),
                .init(title: "Shortcut", detail: "⌘1 opens Trial Balance; ⌘6 opens Ledger."),
                .init(title: "Drill-down", detail: "Clickable rows open the related ledger or voucher.")
            ])
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading) {
            Text("Reports").font(.headline).padding(12)
            List(selection: $vm.selection) {
                ForEach(ReportSelection.visibleCases(isInventoryEnabled: env.companyContext?.isInventoryEnabled ?? false)) { r in
                    Text(r.title).tag(r)
                }
            }
        }
    }

    @ViewBuilder
    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            ScrollView {
                VStack(alignment: .leading) {
                    switch vm.selection {
                    case .trialBalance:  trialBalanceSection
                    case .profitLoss:    profitLossSection
                    case .balanceSheet:  balanceSheetSection
                    case .gstSummary:    gstSummarySection
                    case .gstFiling:     gstFilingSection
                    case .dayBook:       dayBookSection
                    case .ledger:        ledgerSection
                    case .cashBook, .bankBook: ledgerSection
                    case .receivables:   receivablesSection
                    case .payables:      payablesSection
                    case .stockMovement: stockMovementSection
                    case .stockRegister: stockRegisterSection
                    case .outstanding:   outstandingSection
                    case .stockValuation: stockSummarySection
                    case .cashFlow:      cashFlowSection
                    case .stockAgeing:   stockAgeingSection
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            switch vm.selection {
            case .trialBalance, .balanceSheet, .outstanding, .stockValuation, .stockAgeing:
                DatePicker("As of", selection: $vm.asOf, displayedComponents: .date)
                    .onChange(of: vm.asOf) { _, _ in vm.reload() }
            case .dayBook:
                Button("Previous day") { vm.previousDay() }
                DatePicker("Day", selection: $vm.selectedDay, displayedComponents: .date)
                    .onChange(of: vm.selectedDay) { _, day in vm.loadDayBook(day: day) }
                Button("Next day") { vm.nextDay() }
            case .profitLoss, .gstSummary, .gstFiling, .ledger, .cashBook, .bankBook, .receivables, .payables, .stockMovement, .stockRegister, .cashFlow:
                DatePicker("From", selection: $vm.fromDate, displayedComponents: .date)
                DatePicker("To", selection: $vm.toDate, displayedComponents: .date)
            }
            if vm.selection == .ledger {
                Picker("Account", selection: $vm.ledgerAccountId) {
                    Text("Select…").tag(Account.ID?.none)
                    ForEach(vm.accounts) { a in
                        Text("\(a.code) — \(a.name.capitalized)").tag(Optional(a.id))
                    }
                }
                .frame(minWidth: 280)
            } else if vm.selection == .cashBook || vm.selection == .bankBook {
                Picker("Account", selection: $vm.cashBankAccountId) {
                    Text("Select…").tag(Account.ID?.none)
                    ForEach(vm.cashBankAccounts) { a in
                        Text("\(a.code) — \(a.name.capitalized)").tag(Optional(a.id))
                    }
                }
                .frame(minWidth: 280)
            }
            if [.trialBalance, .profitLoss, .balanceSheet].contains(vm.selection) {
                Toggle("Compare prior year", isOn: $vm.comparativeEnabled)
                    .toggleStyle(.switch)
                    .keyboardShortcut("n", modifiers: [.option])
                    .help("Add a prior-year comparative column (⌥N)")
                    .onChange(of: vm.comparativeEnabled) { _, _ in vm.reload() }
            }
            Spacer()
            Button("Refresh") { vm.reload() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(12)
    }

}

@MainActor
enum ReportsNavigation {
    static func openVoucher(_ voucherId: Voucher.ID, router: AppRouter) {
        router.present(.editVoucher(voucherId))
    }
}
