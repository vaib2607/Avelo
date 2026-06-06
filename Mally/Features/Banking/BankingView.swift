import SwiftUI

public struct BankingView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: BankingViewModel?
    @State private var showImport: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm {
                content(vm: vm)
            } else { ProgressView() }
        }
        .navigationTitle("Banking")
        .toolbar {
            ToolbarItem {
                Button { showImport = true } label: {
                    Label("Import statement", systemImage: "tray.and.arrow.down")
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

    @ViewBuilder
    private func content(vm: BankingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            }
            .padding(12)
            Divider()
            ScrollView {
                if let r = vm.result {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Summary") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Book balance: \(Currency.formatPaise(r.bookBalancePaise))").monospacedDigit()
                                Text("Bank balance: \(Currency.formatPaise(r.bankBalancePaise))").monospacedDigit()
                                Text("Difference: \(Currency.formatPaise(r.bookBalancePaise - r.bankBalancePaise))")
                                    .monospacedDigit()
                                    .foregroundStyle(r.bookBalancePaise - r.bankBalancePaise == 0 ? .green : .red)
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
        }
    }

    private func setup() {
        guard let ctx = env.companyContext else { return }
        if vm == nil || vm?.companyId != ctx.companyId {
            vm = BankingViewModel(companyId: ctx.companyId, db: ctx.database)
            vm?.reload()
        }
    }
}
