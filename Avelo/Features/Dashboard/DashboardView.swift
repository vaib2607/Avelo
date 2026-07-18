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
                ModuleFooterBar(items: [
                    .init(title: "Next", detail: "Press F4–F9 for a new voucher, or ⌘4 to switch to Reports."),
                    .init(title: "Shortcut", detail: "F4–F9 and ⌃F8/⌃F9 map to the Tally voucher families."),
                    .init(title: "Context", detail: "Company, FY, and module are always shown above.")
                ])
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
                    quickButton("Credit Note", "⌃F8", .newCreditNote, "doc.badge.plus")
                    quickButton("Debit Note", "⌃F9", .newDebitNote, "document.badge.minus")
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
        ModuleChrome(
            title: "Dashboard",
            subtitle: "Your offline Tally-style control center for company context, quick entry, and live totals.",
            hints: [
                .init(title: "Dashboard", key: "⌘1"),
                .init(title: "Vouchers", key: "⌘2"),
                .init(title: "Reports", key: "⌘4")
            ]
        )
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
            if env.companyContext?.isInventoryEnabled == true {
                KPICard(title: "Stock Value",value: vm.stockValuePaise, accent: .teal)
            }
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
                LabeledMoney(title: "Total", paise: cashPositionTotalPaise, bold: true)
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
                        let net = monthlyNetPaise(for: row)
                        Text(Currency.formatPaise(net))
                            .monospacedDigit()
                            .foregroundStyle(net >= 0 ? AppColors.moneyPositive : AppColors.moneyNegative)
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

    private var cashPositionTotalPaise: Int64 {
        (try? CheckedMath.add(
            vm.cashBalancePaise,
            vm.bankBalancePaise,
            context: "calculating dashboard cash position total"
        )) ?? 0
    }

    private func monthlyNetPaise(for row: DashboardViewModel.MonthlyTotal) -> Int64 {
        (try? CheckedMath.subtract(
            row.incomePaise,
            row.expensePaise,
            context: "calculating dashboard monthly profit and loss net"
        )) ?? 0
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
                .foregroundStyle(value >= 0 ? AppColors.moneyPositive : AppColors.moneyNegative)
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
            if bal >= 0 {
                dr = (try? CheckedMath.add(dr, bal, context: "summing dashboard live debit total")) ?? 0
            } else {
                let creditMagnitude = (try? CheckedMath.abs(bal, context: "calculating dashboard live credit magnitude")) ?? 0
                cr = (try? CheckedMath.add(cr, creditMagnitude, context: "summing dashboard live credit total")) ?? 0
            }
        }
        return (dr, cr)
    }

    var body: some View {
        let t = totals
        let balanced = t.debit == t.credit
        return GroupBox("Trial Balance (live)") {
            HStack(spacing: 16) {
                Label {
                    Text(
                        cache.tree == nil
                            ? "stale"
                            : (balanced
                                ? "balanced"
                                : "off by \(Currency.formatAbsolutePaise((try? CheckedMath.subtract(t.debit, t.credit, context: "calculating dashboard trial balance difference")) ?? 0))")
                    )
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
                Button("Rebuild") { Task { await cache.reload() } }
                    .controlSize(.small)
            }
            .padding(6)
        }
    }
}
