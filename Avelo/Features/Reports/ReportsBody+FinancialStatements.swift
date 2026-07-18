import SwiftUI

@MainActor
extension ReportsBody {
    private func safeDebitLessCredit(_ row: ReportResult.TrialBalanceRow, context: String) -> String {
        do {
            return Currency.formatPaise(try CheckedMath.subtract(row.debitPaise, row.creditPaise, context: context))
        } catch {
            return "Calculation error"
        }
    }

    private func safeCreditLessDebit(_ row: ReportResult.TrialBalanceRow, context: String) -> String {
        do {
            return Currency.formatPaise(try CheckedMath.subtract(row.creditPaise, row.debitPaise, context: context))
        } catch {
            return "Calculation error"
        }
    }

    var trialBalanceSection: some View {
        let rows = vm.trialBalance
        let debitTotal = try? CheckedMath.sum(rows.map(\.debitPaise), context: "summing trial balance debit total for UI")
        let creditTotal = try? CheckedMath.sum(rows.map(\.creditPaise), context: "summing trial balance credit total for UI")
        let difference: Int64? = if let debitTotal, let creditTotal {
            try? CheckedMath.subtract(debitTotal, creditTotal, context: "calculating trial balance difference for UI")
        } else {
            nil
        }
        let comparativeByAccount = Dictionary(uniqueKeysWithValues: vm.comparativeTrialBalance.map { ($0.id, $0) })
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
                if let difference {
                    Label(
                        "Trial balance does not tie out. Difference: \(Currency.formatAbsolutePaise(difference)) on the \(difference > 0 ? "debit" : "credit") side.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else if debitTotal != nil && creditTotal != nil {
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
                    TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                        if vm.comparativeEnabled {
                            if let prior = comparativeByAccount[r.id] {
                                Text(safeDebitLessCredit(prior, context: "rendering trial balance comparative amount")).monospacedDigit()
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(vm.comparativeEnabled ? nil : 0)
                }
                HStack {
                    Spacer()
                    Text("Debit total: \(debitTotal.map { Currency.formatPaise($0) } ?? "Calculation error")").monospacedDigit().bold()
                    Text("Credit total: \(creditTotal.map { Currency.formatPaise($0) } ?? "Calculation error")").monospacedDigit().bold()
                }
            }
        }
    }

    @ViewBuilder
    var profitLossSection: some View {
        if let pl = vm.profitLoss {
            let comparativeIncomeRows: [ReportResult.TrialBalanceRow] = vm.comparativeProfitLoss.map { Array($0.income) } ?? []
            let comparativeExpenseRows: [ReportResult.TrialBalanceRow] = vm.comparativeProfitLoss.map { Array($0.expenses) } ?? []
            let comparativeIncome = Dictionary(uniqueKeysWithValues: comparativeIncomeRows.map { ($0.id, $0) })
            let comparativeExpense = Dictionary(uniqueKeysWithValues: comparativeExpenseRows.map { ($0.id, $0) })
            VStack(alignment: .leading, spacing: 8) {
                Text("Income").font(.headline)
                Table(pl.income) {
                    TableColumn("Account") { r in
                        Button(r.accountName) { openLedger(r.id) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Amount (₹)", content: { (r: ReportResult.TrialBalanceRow) in
                        Text(safeCreditLessDebit(r, context: "rendering profit and loss income amount")).monospacedDigit()
                    })
                    TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                        if vm.comparativeEnabled {
                            if let prior = comparativeIncome[r.id] {
                                Text(safeCreditLessDebit(prior, context: "rendering profit and loss comparative income amount")).monospacedDigit()
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(vm.comparativeEnabled ? nil : 0)
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
                        Text(safeDebitLessCredit(r, context: "rendering profit and loss expense amount")).monospacedDigit()
                    })
                    TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                        if vm.comparativeEnabled {
                            if let prior = comparativeExpense[r.id] {
                                Text(safeDebitLessCredit(prior, context: "rendering profit and loss comparative expense amount")).monospacedDigit()
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(vm.comparativeEnabled ? nil : 0)
                }
                Text("Total expense: \(Currency.formatPaise(pl.totalExpensesPaise))").monospacedDigit().bold()
                Divider()
                Text("Net: \(Currency.formatPaise(pl.netProfitPaise))")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(pl.netProfitPaise >= 0 ? .green : .red)
                if vm.comparativeEnabled, let comparativePL = vm.comparativeProfitLoss {
                    Text("Prior year net: \(Currency.formatPaise(comparativePL.netProfitPaise))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
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
        if vm.isLoading {
            ProgressView("Loading Balance Sheet…")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let error = vm.error {
            ContentUnavailableView(
                "Balance Sheet unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("\(error.localizedMessage)\nAs of \(DateFormatters.formatIsoDate(vm.asOf)).")
            )
            .frame(maxWidth: .infinity, minHeight: 160)
            Button("Refresh") { vm.reload() }
                .keyboardShortcut("r", modifiers: .command)
        } else if let bs = vm.balanceSheet {
            let comparativeAssets = Dictionary(uniqueKeysWithValues: (vm.comparativeBalanceSheet?.assets.flatMap { $0.rows } ?? []).map { ($0.id, $0) })
            let comparativeLiabilities = Dictionary(uniqueKeysWithValues: (vm.comparativeBalanceSheet?.liabilities.flatMap { $0.rows } ?? []).map { ($0.id, $0) })
            let comparativeEquity = Dictionary(uniqueKeysWithValues: (vm.comparativeBalanceSheet?.equity.flatMap { $0.rows } ?? []).map { ($0.id, $0) })
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assets").font(.headline)
                    Table(bs.assets.flatMap { $0.rows }) {
                        TableColumn("Account") { r in
                            Button(r.accountName) { openLedger(r.id) }
                                .buttonStyle(.plain)
                        }
                        TableColumn("Amount (₹)") { r in
                            Text(safeDebitLessCredit(r, context: "rendering balance sheet asset amount")).monospacedDigit()
                        }
                        TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                            if vm.comparativeEnabled {
                                if let prior = comparativeAssets[r.id] {
                                    Text(safeDebitLessCredit(prior, context: "rendering balance sheet comparative asset amount")).monospacedDigit()
                                } else {
                                    Text("—").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(vm.comparativeEnabled ? nil : 0)
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
                            Text(safeCreditLessDebit(r, context: "rendering balance sheet liability amount")).monospacedDigit()
                        }
                        TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                            if vm.comparativeEnabled {
                                if let prior = comparativeLiabilities[r.id] {
                                    Text(safeCreditLessDebit(prior, context: "rendering balance sheet comparative liability amount")).monospacedDigit()
                                } else {
                                    Text("—").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(vm.comparativeEnabled ? nil : 0)
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
                            Text(safeCreditLessDebit(r, context: "rendering balance sheet equity amount")).monospacedDigit()
                        }
                        TableColumn(vm.comparativeEnabled ? "Prior Year (₹)" : "") { r in
                            if vm.comparativeEnabled {
                                if let prior = comparativeEquity[r.id] {
                                    Text(safeCreditLessDebit(prior, context: "rendering balance sheet comparative equity amount")).monospacedDigit()
                                } else {
                                    Text("—").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(vm.comparativeEnabled ? nil : 0)
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
