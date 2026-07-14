import SwiftUI

private enum BankingSection: String, CaseIterable, Identifiable {
    case reconciliation = "Reconciliation"
    case cheques = "Cheques"
    var id: String { rawValue }
}

public struct BankingView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: BankingViewModel?
    @State private var chequesVM: ChequesViewModel?
    @State private var showImport: Bool = false
    @State private var section: BankingSection = .reconciliation

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(BankingSection.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            switch section {
            case .reconciliation:
                BankingContent(vm: vm)
            case .cheques:
                ChequesContent(vm: chequesVM)
            }
        }
        .navigationTitle("Banking")
        .toolbar {
            ToolbarItem {
                if section == .reconciliation {
                    Button { showImport = true } label: {
                        Label("Import statement", systemImage: "tray.and.arrow.down")
                    }
                    .keyboardShortcut("i", modifiers: .command)
                }
            }
        }
        .onAppear { setup() }
        .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
        .sheet(isPresented: $showImport) {
            if let ctx = env.companyContext {
                ImportStatementSheet(companyId: ctx.companyId, db: ctx.database, accounts: vm?.accounts ?? [])
            }
        }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            chequesVM = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = BankingViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
        if chequesVM == nil || chequesVM?.companyId != ctx.companyId {
            let model = ChequesViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            chequesVM = model
        }
    }
}

@MainActor
private struct BankingContent: View {
    let vm: BankingViewModel?

    var body: some View {
        if let vm {
            BankingBody(vm: vm)
        } else { ProgressView() }
    }
}

@MainActor
private struct BankingBody: View {
    @Bindable var vm: BankingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleChrome(
                title: "Banking",
                subtitle: "Reconciliation-focused bank workspace with offline statement import and matched entries.",
                hints: [
                    .init(title: "Reconcile", key: "⌘R"),
                    .init(title: "Import", key: "⌘I")
                ]
            )
            HStack {
                Picker("Account", selection: $vm.selectedAccountId) {
                    Text("Select…").tag(Account.ID?.none)
                    ForEach(vm.accounts) { a in
                        Text("\(a.code) — \(a.name)").tag(Optional(a.id))
                    }
                }
                .frame(minWidth: 320)
                .onChange(of: vm.selectedAccountId) { _, _ in vm.reconcile() }
                DatePicker("As of", selection: $vm.asOf, displayedComponents: .date)
                    .onChange(of: vm.asOf) { _, _ in vm.reconcile() }
                Spacer()
                Button("Reconcile") { vm.reconcile() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .padding(12)
            Divider()
            ScrollView {
                if let r = vm.result {
                    let difference = (try? CheckedMath.subtract(
                        r.bookBalancePaise,
                        r.bankBalancePaise,
                        context: "calculating banking reconciliation difference"
                    )) ?? 0
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Summary") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Book balance: \(Currency.formatPaise(r.bookBalancePaise))").monospacedDigit()
                                Text("Bank balance: \(Currency.formatPaise(r.bankBalancePaise))").monospacedDigit()
                                Text("Difference: \(Currency.formatPaise(difference))")
                                    .monospacedDigit()
                                    .foregroundStyle(difference == 0 ? .green : .red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        GroupBox("Matched") {
                            Table(r.matched) {
                                TableColumn("Date") { m in
                                    Text(DateFormatters.userDate.string(from: m.statementEntry.date))
                                }
                                TableColumn("Statement narration", value: \.statementEntry.narration)
                                TableColumn("Voucher", value: \.voucherNumber)
                                TableColumn("Amount (₹)") { m in
                                    Text(Currency.formatPaise(m.statementEntry.amountPaise)).monospacedDigit()
                                }
                            }
                            .frame(minHeight: 200)
                        }
                        GroupBox("Unmatched statement entries") {
                            Table(r.unmatchedStatement) {
                                TableColumn("Date") { e in
                                    Text(DateFormatters.userDate.string(from: e.date))
                                }
                                TableColumn("Narration", value: \.narration)
                                TableColumn("Amount (₹)") { e in
                                    Text(Currency.formatPaise(e.amountPaise)).monospacedDigit()
                                }
                            }
                            .frame(minHeight: 160)
                        }
                    }
                    .padding(16)
                } else {
                    Text("Select a bank account to reconcile.")
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
            }
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Select a bank account, then reconcile or import a statement."),
                .init(title: "Shortcut", detail: "⌘I opens import, ⌘R reruns reconciliation."),
                .init(title: "Workflow", detail: "Matched rows map statement entries back to vouchers.")
            ])
        }
    }
}
