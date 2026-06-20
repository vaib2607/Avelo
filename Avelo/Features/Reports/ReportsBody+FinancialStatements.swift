import SwiftUI

@MainActor
extension ReportsBody {
    var trialBalanceSection: some View {
        let rows = vm.trialBalance
        let debitTotal = rows.reduce(Int64(0)) { $0 + $1.debitPaise }
        let creditTotal = rows.reduce(Int64(0)) { $0 + $1.creditPaise }
        let difference = debitTotal - creditTotal
        return Group {
            if rows.isEmpty {
                EmptyStateView(
                    title: "No trial balance yet",
                    message: "There are no posted vouchers in this financial year yet.",
                    systemImage: "sum",
                    actionTitle: "Refresh",
                    action: { vm.reload() }
                )
            } else {
                if difference != 0 {
                    Label(
                        "Trial balance does not tie out. Difference: \(Currency.formatPaise(abs(difference))) on the \(difference > 0 ? "debit" : "credit") side.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Label("Books are balanced.", systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
                Table(rows) {
                    TableColumn("Account") { r in
                        Button(r.accountName) { openLedger(r.id) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Group", value: \.groupPath)
                    TableColumn("Debit (₹)") { r in
                        Text(Currency.formatPaise(r.debitPaise)).monospacedDigit()
                    }
                    TableColumn("Credit (₹)") { r in
                        Text(Currency.formatPaise(r.creditPaise)).monospacedDigit()
                    }
                }
                HStack {
                    Spacer()
                    Text("Debit total: \(Currency.formatPaise(debitTotal))").monospacedDigit().bold()
                    Text("Credit total: \(Currency.formatPaise(creditTotal))").monospacedDigit().bold()
                }
            }
        }
    }

    @ViewBuilder
    var profitLossSection: some View {
        if let pl = vm.profitLoss {
            VStack(alignment: .leading, spacing: 8) {
                Text("Income").font(.headline)
                Table(pl.income) {
                    TableColumn("Account") { r in
                        Button(r.accountName) { openLedger(r.id) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Amount (₹)", content: { (r: ReportResult.TrialBalanceRow) in
                        Text(Currency.formatPaise(r.debitPaise - r.creditPaise)).monospacedDigit()
                    })
                }
                Text("Total income: \(Currency.formatPaise(pl.totalIncomePaise))").monospacedDigit().bold()
                Divider()
                Text("Expense").font(.headline)
                Table(pl.expenses) {
                    TableColumn("Account") { r in
                        Button(r.accountName) { openLedger(r.id) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Amount (₹)", content: { (r: ReportResult.TrialBalanceRow) in
                        Text(Currency.formatPaise(r.creditPaise - r.debitPaise)).monospacedDigit()
                    })
                }
                Text("Total expense: \(Currency.formatPaise(pl.totalExpensesPaise))").monospacedDigit().bold()
                Divider()
                Text("Net: \(Currency.formatPaise(pl.netProfitPaise))")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(pl.netProfitPaise >= 0 ? .green : .red)
            }
        } else {
            EmptyStateView(
                title: "No profit and loss data",
                message: "Profit and loss appears after income and expense vouchers are posted for the selected period.",
                systemImage: "chart.line.uptrend.xyaxis",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }
    @ViewBuilder
    var balanceSheetSection: some View {
        if let bs = vm.balanceSheet {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assets").font(.headline)
                    Table(bs.assets.flatMap { $0.rows }) {
                        TableColumn("Account") { r in
                            Button(r.accountName) { openLedger(r.id) }
                                .buttonStyle(.plain)
                        }
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.debitPaise - r.creditPaise)).monospacedDigit()
                        }
                    }
                    Text("Total assets: \(Currency.formatPaise(bs.totalAssetsPaise))").monospacedDigit().bold()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Liabilities").font(.headline)
                    Table(bs.liabilities.flatMap { $0.rows }) {
                        TableColumn("Account") { r in
                            Button(r.accountName) { openLedger(r.id) }
                                .buttonStyle(.plain)
                        }
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.creditPaise - r.debitPaise)).monospacedDigit()
                        }
                    }
                    Text("Total liabilities: \(Currency.formatPaise(bs.totalLiabilitiesPaise))").monospacedDigit().bold()
                    Divider()
                    Text("Equity").font(.headline)
                    Table(bs.equity.flatMap { $0.rows }) {
                        TableColumn("Account") { r in
                            Button(r.accountName) { openLedger(r.id) }
                                .buttonStyle(.plain)
                        }
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.creditPaise - r.debitPaise)).monospacedDigit()
                        }
                    }
                    Text("Total equity: \(Currency.formatPaise(bs.totalEquityPaise))").monospacedDigit().bold()
                }
            }
        } else {
            EmptyStateView(
                title: "No balance sheet data",
                message: "Balance sheet rows appear once assets, liabilities, or equity accounts have posted activity.",
                systemImage: "scale.3d",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }
    @ViewBuilder
    var cashFlowSection: some View {
        if let s = vm.cashFlow {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cash Flow").font(.headline)
                Table(s.rows) {
                    TableColumn("Section") { row in
                        Text(row.section.displayName)
                    }
                    TableColumn("Account", value: \.accountName)
                    TableColumn("Inflow (₹)") { row in
                        Text(Currency.formatPaise(row.inflowPaise)).monospacedDigit()
                    }
                    TableColumn("Outflow (₹)") { row in
                        Text(Currency.formatPaise(row.outflowPaise)).monospacedDigit()
                    }
                    TableColumn("Net (₹)") { row in
                        Text(Currency.formatPaise(row.netPaise)).monospacedDigit()
                    }
                }
                Text("Net cash flow: \(Currency.formatPaise(s.netCashFlowPaise))").monospacedDigit().bold()
            }
        } else {
            EmptyStateView(
                title: "No cash flow",
                message: "Cash flow appears when cash or bank ledger movements exist in the selected period.",
                systemImage: "indianrupeesign.arrow.circlepath",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

}
