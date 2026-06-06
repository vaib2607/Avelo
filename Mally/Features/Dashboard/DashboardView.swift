import SwiftUI

public struct DashboardView: View {

    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = DashboardViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                accountTreeStrip
                kpiGrid
                cashPosition
                monthlyPLSection
                recentVouchersSection
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .task(id: env.companyContext?.companyId) { reload() }
    }

    @ViewBuilder
    private var accountTreeStrip: some View {
        if let tree = env.accountTree {
            HStack(spacing: 16) {
                Label {
                    Text("Account tree: \(tree.tree == nil ? "stale" : "ready")")
                } icon: {
                    Image(systemName: tree.tree == nil ? "exclamationmark.triangle" : "checkmark.seal")
                        .foregroundStyle(tree.tree == nil ? .orange : .green)
                }
                if let t = tree.tree {
                    Text("\(t.roots.count) root groups · \(t.allLedgers.count) ledgers")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rebuild") { env.accountTree?.reload() }
                    .controlSize(.small)
            }
            .font(.caption)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Welcome back").font(.title2.bold())
                if let fy = env.companyContext?.financialYear {
                    Text("Financial year: \(fy.label)")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                env.router.present(.newVoucher)
            } label: {
                Label("New Voucher", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
        }
    }

    @ViewBuilder
    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            KPICard(title: "Cash",       value: vm.cashBalancePaise,    accent: .green)
            KPICard(title: "Bank",       value: vm.bankBalancePaise,    accent: .blue)
            KPICard(title: "Receivables",value: vm.receivablesPaise,    accent: .indigo)
            KPICard(title: "Payables",   value: vm.payablesPaise,       accent: .orange)
            KPICard(title: "Month Sales",value: vm.monthSalesPaise,     accent: .purple)
            KPICard(title: "Month Purchases", value: vm.monthPurchasesPaise, accent: .pink)
            KPICard(title: "GST Payable",value: vm.gstPayablePaise,     accent: .red)
            KPICard(title: "Stock Value",value: vm.stockValuePaise,     accent: .teal)
        }
    }

    @ViewBuilder
    private var cashPosition: some View {
        GroupBox("Cash Position") {
            HStack(spacing: 20) {
                LabeledMoney(title: "Cash in hand", paise: vm.cashBalancePaise)
                Divider().frame(height: 40)
                LabeledMoney(title: "At bank", paise: vm.bankBalancePaise)
                Divider().frame(height: 40)
                LabeledMoney(title: "Total", paise: vm.cashBalancePaise + vm.bankBalancePaise, bold: true)
                Spacer()
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var monthlyPLSection: some View {
        GroupBox("Profit & Loss by Month") {
            if vm.monthlyPL.isEmpty {
                Text("No data in current financial year.").foregroundStyle(.secondary)
                    .padding(8)
            } else {
                Table(vm.monthlyPL) {
                    TableColumn("Month", value: \.monthLabel)
                    TableColumn("Income (₹)") { row in
                        Text(Currency.formatPaise(row.incomePaise)).monospacedDigit()
                    }
                    TableColumn("Expense (₹)") { row in
                        Text(Currency.formatPaise(row.expensePaise)).monospacedDigit()
                    }
                    TableColumn("Net (₹)") { row in
                        Text(Currency.formatPaise(row.incomePaise - row.expensePaise))
                            .monospacedDigit()
                            .foregroundStyle(row.incomePaise - row.expensePaise >= 0 ? .green : .red)
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }

    @ViewBuilder
    private var recentVouchersSection: some View {
        GroupBox("Recent Vouchers") {
            if vm.recentVouchers.isEmpty {
                Text("No vouchers yet.").foregroundStyle(.secondary).padding(8)
            } else {
                Table(vm.recentVouchers) {
                    TableColumn("Date") { v in
                        Text(DateFormatters.userDate.string(from: v.date))
                    }
                    TableColumn("Number", value: \.number)
                    TableColumn("Type", value: \.voucherTypeCode.rawValue)
                    TableColumn("Amount (₹)") { v in
                        Text(Currency.formatPaise(v.totalPaise)).monospacedDigit()
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }

    private func reload() {
        guard let ctx = env.companyContext else { return }
        vm.reload(ctx: ctx)
    }
}

private struct KPICard: View {
    let title: String
    let value: Int64
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Currency.formatPaise(value))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LabeledMoney: View {
    let title: String
    let paise: Int64
    var bold: Bool = false
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Currency.formatPaise(paise))
                .font(bold ? .title3.bold() : .body)
                .monospacedDigit()
        }
    }
}
