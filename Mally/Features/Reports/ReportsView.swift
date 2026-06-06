import SwiftUI

public struct ReportsView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: ReportsViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm {
                content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .onAppear { setup() }
        .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
    }

    @ViewBuilder
    private func content(vm: ReportsViewModel) -> some View {
        HSplitView {
            sidebar(vm: vm)
                .frame(minWidth: 220)
            main(vm: vm)
                .frame(minWidth: 540)
        }
    }

    @ViewBuilder
    private func sidebar(vm: ReportsViewModel) -> some View {
        VStack(alignment: .leading) {
            Text("Report").font(.headline).padding(12)
            List(selection: $vm.selection) {
                ForEach(ReportSelection.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
        }
    }

    @ViewBuilder
    private func main(vm: ReportsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            controls(vm: vm)
            Divider()
            ScrollView {
                VStack(alignment: .leading) {
                    switch vm.selection {
                    case .trialBalance:  trialBalanceSection(vm: vm)
                    case .profitLoss:    profitLossSection(vm: vm)
                    case .balanceSheet:  balanceSheetSection(vm: vm)
                    case .gstSummary:    gstSummarySection(vm: vm)
                    case .dayBook:       dayBookSection(vm: vm)
                    case .ledger:        ledgerSection(vm: vm)
                    case .outstanding:   outstandingSection(vm: vm)
                    case .stockValuation: stockValuationSection(vm: vm)
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func controls(vm: ReportsViewModel) -> some View {
        HStack {
            switch vm.selection {
            case .trialBalance, .balanceSheet, .outstanding, .stockValuation:
                DatePicker("As of", selection: $vm.asOf, displayedComponents: .date)
            case .profitLoss, .gstSummary, .dayBook, .ledger:
                DatePicker("From", selection: $vm.fromDate, displayedComponents: .date)
                DatePicker("To", selection: $vm.toDate, displayedComponents: .date)
            }
            if vm.selection == .ledger {
                Picker("Account", selection: $vm.ledgerAccountId) {
                    Text("Select…").tag(Account.ID?.none)
                    ForEach(vm.accounts) { a in
                        Text("\(a.code) — \(a.name)").tag(Optional(a.id))
                    }
                }
                .frame(minWidth: 260)
            }
            Spacer()
            Button("Refresh") { vm.reload() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .onChange(of: vm.selection) { _, _ in vm.reload() }
        .onChange(of: vm.asOf) { _, _ in vm.reload() }
        .onChange(of: vm.fromDate) { _, _ in vm.reload() }
        .onChange(of: vm.toDate) { _, _ in vm.reload() }
        .onChange(of: vm.ledgerAccountId) { _, _ in vm.reload() }
    }

    @ViewBuilder
    private func trialBalanceSection(vm: ReportsViewModel) -> some View {
        Table(vm.trialBalance) {
            TableColumn("Code", value: \.accountCode)
            TableColumn("Account", value: \.accountName)
            TableColumn("Debit (₹)") { r in
                Text(Currency.formatPaise(r.debitPaise)).monospacedDigit()
            }
            TableColumn("Credit (₹)") { r in
                Text(Currency.formatPaise(r.creditPaise)).monospacedDigit()
            }
        }
        let totalDr = vm.trialBalance.reduce(Int64(0)) { $0 + $1.debitPaise }
        let totalCr = vm.trialBalance.reduce(Int64(0)) { $0 + $1.creditPaise }
        HStack {
            Spacer()
            Text("Totals — Dr \(Currency.formatPaise(totalDr))   Cr \(Currency.formatPaise(totalCr))")
                .monospacedDigit()
                .bold()
        }
    }

    @ViewBuilder
    private func profitLossSection(vm: ReportsViewModel) -> some View {
        if let pl = vm.profitLoss {
            VStack(alignment: .leading, spacing: 8) {
                Text("Income").font(.headline)
                Table(pl.income) {
                    TableColumn("Account", value: \.accountName)
                    TableColumn("Amount (₹)") { r in
                        Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                    }
                }
                Text("Total income: \(Currency.formatPaise(pl.totalIncomePaise))").monospacedDigit().bold()
                Divider()
                Text("Expense").font(.headline)
                Table(pl.expenses) {
                    TableColumn("Account", value: \.accountName)
                    TableColumn("Amount (₹)") { r in
                        Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                    }
                }
                Text("Total expense: \(Currency.formatPaise(pl.totalExpensesPaise))").monospacedDigit().bold()
                Divider()
                Text("Net: \(Currency.formatPaise(pl.netProfitPaise))")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(pl.netProfitPaise >= 0 ? .green : .red)
            }
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func balanceSheetSection(vm: ReportsViewModel) -> some View {
        if let bs = vm.balanceSheet {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assets").font(.headline)
                    Table(bs.assets) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                        }
                    }
                    Text("Total assets: \(Currency.formatPaise(bs.totalAssetsPaise))").monospacedDigit().bold()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Liabilities").font(.headline)
                    Table(bs.liabilities) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                        }
                    }
                    Text("Total liabilities: \(Currency.formatPaise(bs.totalLiabilitiesPaise))").monospacedDigit().bold()
                    Divider()
                    Text("Equity").font(.headline)
                    Table(bs.equity) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                        }
                    }
                    Text("Total equity: \(Currency.formatPaise(bs.totalEquityPaise))").monospacedDigit().bold()
                }
            }
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func gstSummarySection(vm: ReportsViewModel) -> some View {
        if let g = vm.gstSummary {
            VStack(alignment: .leading, spacing: 6) {
                row("Output taxable", g.outputTaxablePaise)
                row("Output tax", g.outputTaxPaise)
                row("Input taxable", g.inputTaxablePaise)
                row("Input tax (credit)", g.inputTaxPaise)
                row("IGST", g.igstPaise)
                row("CGST", g.cgstPaise)
                row("SGST", g.sgstPaise)
                Divider()
                row("Net payable", g.netPayablePaise, bold: true)
            }
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func row(_ title: String, _ paise: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Currency.formatPaise(paise))
                .monospacedDigit()
                .bold(bold)
        }
    }

    @ViewBuilder
    private func dayBookSection(vm: ReportsViewModel) -> some View {
        Table(vm.dayBook) {
            TableColumn("Date") { r in
                Text(DateFormatters.userDate.string(from: r.date))
            }
            TableColumn("Number", value: \.number)
            TableColumn("Type", value: \.typeCode)
            TableColumn("Narration", value: \.narration)
            TableColumn("Amount (₹)") { r in
                Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func ledgerSection(vm: ReportsViewModel) -> some View {
        if let l = vm.ledger {
            VStack(alignment: .leading, spacing: 8) {
                Text(l.accountName).font(.headline)
                Table(l.entries) {
                    TableColumn("Date") { e in
                        Text(DateFormatters.userDate.string(from: e.date))
                    }
                    TableColumn("Voucher", value: \.voucherNumber)
                    TableColumn("Particulars", value: \.particulars)
                    TableColumn("Debit (₹)") { e in
                        Text(Currency.formatPaise(e.debitPaise)).monospacedDigit()
                    }
                    TableColumn("Credit (₹)") { e in
                        Text(Currency.formatPaise(e.creditPaise)).monospacedDigit()
                    }
                }
                Text("Opening: \(Currency.formatPaise(l.openingBalancePaise))   Closing: \(Currency.formatPaise(l.closingBalancePaise))")
                    .monospacedDigit()
            }
        } else { Text("Select an account.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func outstandingSection(vm: ReportsViewModel) -> some View {
        if let o = vm.outstanding {
            Table(o.rows) {
                TableColumn("Party", value: \.partyName)
                TableColumn("As of") { r in
                    Text(DateFormatters.userDate.string(from: r.asOf))
                }
                TableColumn("Amount (₹)") { r in
                    Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                }
                TableColumn("Age (days)") { r in
                    Text("\(r.ageInDays)")
                }
            }
            Text("Total: \(Currency.formatPaise(o.totalPaise))").monospacedDigit().bold()
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func stockValuationSection(vm: ReportsViewModel) -> some View {
        if let s = vm.stockValuation {
            Table(s.rows) {
                TableColumn("Code", value: \.itemCode)
                TableColumn("Item", value: \.itemName)
                TableColumn("Qty") { r in
                    Text(String(format: "%.3f", r.quantity))
                }
                TableColumn("Rate (₹)") { r in
                    Text(Currency.formatPaise(r.ratePaise)).monospacedDigit()
                }
                TableColumn("Value (₹)") { r in
                    Text(Currency.formatPaise(r.valuePaise)).monospacedDigit()
                }
            }
            Text("Total: \(Currency.formatPaise(s.totalPaise))").monospacedDigit().bold()
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    private func setup() {
        guard let ctx = env.companyContext else { return }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = ReportsViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            model.asOf = ctx.financialYear.endDate
            model.fromDate = ctx.financialYear.startDate
            model.toDate = ctx.financialYear.endDate
            vm = model
            model.reload()
        }
    }
}
