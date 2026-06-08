import SwiftUI

public struct DashboardView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm = DashboardViewModel()

    public init() {}

    public var body: some View {
        @Bindable var vm = vm

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                voucherQuickActions
                accountTreeStrip
                kpiGrid
                cashPosition
                monthlyPLSection
                recentVouchersSection
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .task(id: reloadKey) { reload() }
    }

    private var reloadKey: String {
        let company = env.companyContext?.companyId.uuidString ?? "none"
        return "\(company)-\(env.dataRevision)"
    }

    @ViewBuilder
    private var voucherQuickActions: some View {
        GroupBox("Quick Entry") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickButton("Contra", "F4", .newContra, "arrow.left.arrow.right")
                    quickButton("Payment", "F5", .newPayment, "arrow.up.circle")
                    quickButton("Receipt", "F6", .newReceipt, "arrow.down.circle")
                    quickButton("Journal", "F7", .newJournal, "book.closed")
                    quickButton("Sales", "F8", .newSales, "cart")
                    quickButton("Purchase", "F9", .newPurchase, "bag")
                    quickButton("Credit Note", "F10", .newCreditNote, "doc.badge.plus")
                    quickButton("Debit Note", "F11", .newDebitNote, "doc.badge.minus")
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private func quickButton(_ title: String, _ key: String, _ sheet: RouterSheet, _ symbol: String) -> some View {
        Button {
            env.router.present(sheet)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption)
                Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            .frame(width: 84, height: 64)
        }
        .buttonStyle(.bordered)
        .help("\(title) (\(key))")
    }

    @ViewBuilder
    private var accountTreeStrip: some View {
        if let cache = env.accountTree {
            AccountTreeStrip(cache: cache)
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

private struct AccountTreeStrip: View {
    @Bindable var cache: AccountTreeCache

    /// Live net trial balance computed entirely in-memory from the tree.
    /// Net presentation: each ledger contributes its signed balance to one side.
    private var totals: (debit: Int64, credit: Int64) {
        guard let t = cache.tree else { return (0, 0) }
        var dr: Int64 = 0
        var cr: Int64 = 0
        for ledger in t.allLedgers where ledger.isActive {
            let bal = ledger.balancePaise
            if bal >= 0 { dr += bal } else { cr += -bal }
        }
        return (dr, cr)
    }

    var body: some View {
        let t = totals
        let balanced = t.debit == t.credit
        return GroupBox("Trial Balance (live)") {
            HStack(spacing: 16) {
                Label {
                    Text(cache.tree == nil ? "stale" : (balanced ? "balanced" : "off by \(Currency.formatPaise(abs(t.debit - t.credit)))"))
                } icon: {
                    Image(systemName: cache.tree == nil ? "exclamationmark.triangle"
                          : (balanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                        .foregroundStyle(cache.tree == nil ? .orange : (balanced ? .green : .red))
                }
                Divider().frame(height: 28)
                LabeledMoney(title: "Total debit", paise: t.debit)
                LabeledMoney(title: "Total credit", paise: t.credit)
                if let tree = cache.tree {
                    Divider().frame(height: 28)
                    Text("\(tree.roots.count) groups · \(tree.allLedgers.count) ledgers")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rebuild") { cache.reload() }
                    .controlSize(.small)
            }
            .padding(6)
        }
    }
}
