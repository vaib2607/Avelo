import SwiftUI

public struct ReportsView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var holder = ReportsViewModelHolder()

    public init() {}

    public var body: some View {
        ReportsContent(holder: holder)
            .navigationTitle("Reports")
            .onAppear { setup(); consumePendingLedger() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
            .onChange(of: env.router.pendingLedgerAccountId) { _, _ in consumePendingLedger() }
    }

    private func setup() {
        guard let ctx = env.companyContext else { return }
        if holder.vm == nil || holder.vm?.companyId != ctx.companyId {
            let model = ReportsViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            model.asOf = ctx.financialYear.endDate
            model.fromDate = ctx.financialYear.startDate
            model.toDate = ctx.financialYear.endDate
            model.reload()
            holder.vm = model
        }
    }

    /// Applies a deep-link request from elsewhere (e.g. AccountsView) to show a
    /// specific account's ledger, then clears the request.
    private func consumePendingLedger() {
        guard let accountId = env.router.pendingLedgerAccountId, let vm = holder.vm else { return }
        vm.selection = .ledger
        vm.ledgerAccountId = accountId
        vm.reload()
        env.router.pendingLedgerAccountId = nil
    }
}

@MainActor
final class ReportsViewModelHolder: ObservableObject {
    @Published var vm: ReportsViewModel?
}

@MainActor
private struct ReportsContent: View {
    @ObservedObject var holder: ReportsViewModelHolder

    var body: some View {
        if let vm = holder.vm {
            ReportsBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct ReportsBody: View {
    @ObservedObject var vm: ReportsViewModel

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220)
            main
                .frame(minWidth: 540)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
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
                    case .dayBook:       dayBookSection
                    case .ledger:        ledgerSection
                    case .outstanding:   outstandingSection
                    case .stockValuation: stockValuationSection
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
                .frame(minWidth: 280)
            }
            Spacer()
            Button("Refresh") { vm.reload() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(12)
    }

    private var trialBalanceSection: some View {
        let rows = vm.trialBalance
        let debitTotal = rows.reduce(Int64(0)) { $0 + $1.debitPaise }
        let creditTotal = rows.reduce(Int64(0)) { $0 + $1.creditPaise }
        let difference = debitTotal - creditTotal
        return Group {
            if rows.isEmpty {
                Text("No data.").foregroundStyle(.secondary)
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
                    TableColumn("Account", value: \.accountName)
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
    private var profitLossSection: some View {
        if let pl = vm.profitLoss {
            VStack(alignment: .leading, spacing: 8) {
                Text("Income").font(.headline)
                Table(pl.income) {
                    TableColumn("Account", value: \.accountName)
                    TableColumn("Amount (₹)", content: { (r: ReportResult.TrialBalanceRow) in
                        Text(Currency.formatPaise(r.debitPaise - r.creditPaise)).monospacedDigit()
                    })
                }
                Text("Total income: \(Currency.formatPaise(pl.totalIncomePaise))").monospacedDigit().bold()
                Divider()
                Text("Expense").font(.headline)
                Table(pl.expenses) {
                    TableColumn("Account", value: \.accountName)
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
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var balanceSheetSection: some View {
        if let bs = vm.balanceSheet {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assets").font(.headline)
                    Table(bs.assets.flatMap { $0.rows }) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.debitPaise - r.creditPaise)).monospacedDigit()
                        }
                    }
                    Text("Total assets: \(Currency.formatPaise(bs.totalAssetsPaise))").monospacedDigit().bold()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Liabilities").font(.headline)
                    Table(bs.liabilities.flatMap { $0.rows }) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.creditPaise - r.debitPaise)).monospacedDigit()
                        }
                    }
                    Text("Total liabilities: \(Currency.formatPaise(bs.totalLiabilitiesPaise))").monospacedDigit().bold()
                    Divider()
                    Text("Equity").font(.headline)
                    Table(bs.equity.flatMap { $0.rows }) {
                        TableColumn("Account", value: \.accountName)
                        TableColumn("Amount (₹)") { r in
                            Text(Currency.formatPaise(r.creditPaise - r.debitPaise)).monospacedDigit()
                        }
                    }
                    Text("Total equity: \(Currency.formatPaise(bs.totalEquityPaise))").monospacedDigit().bold()
                }
            }
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var gstSummarySection: some View {
        if let g = vm.gstSummary {
            VStack(alignment: .leading, spacing: 6) {
                row("Output taxable", g.outputTaxablePaise)
                row("Output tax", g.outputTaxPaise)
                row("Input taxable", g.inputTaxablePaise)
                row("Input tax", g.inputTaxPaise)
                row("IGST", g.igstPaise)
                row("CGST", g.cgstPaise)
                row("SGST", g.sgstPaise)
                row("Net payable", g.netPayablePaise, bold: true)
            }
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func row(_ title: String, _ paise: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Currency.formatPaise(paise)).monospacedDigit()
        }
        .font(bold ? .body.bold() : .body)
    }

    @ViewBuilder
    private var dayBookSection: some View {
        let rows = vm.dayBook
        if rows.isEmpty {
            Text("No vouchers in the period.").foregroundStyle(.secondary)
        } else {
            Table(rows) {
                TableColumn("Date") { r in
                    Text(DateFormatters.userDate.string(from: r.date))
                }
                TableColumn("Voucher") { r in
                    Text(r.voucherNumber)
                }
                TableColumn("Type") { r in
                    Text(r.voucherTypeCode.rawValue)
                }
                TableColumn("Particulars") { r in
                    Text(r.narration)
                }
                TableColumn("Amount (₹)") { r in
                    Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var ledgerSection: some View {
        if let l = vm.ledger {
            VStack(alignment: .leading, spacing: 8) {
                Text(l.accountName).font(.headline)
                Table(l.entries) {
                    TableColumn("Date") { e in
                        Text(DateFormatters.userDate.string(from: e.date))
                    }
                    TableColumn("Voucher", value: \.voucherNumber)
                    TableColumn("Particulars", value: \.narration)
                    TableColumn("Debit (₹)") { e in
                        Text(Currency.formatPaise(e.debitPaise)).monospacedDigit()
                    }
                    TableColumn("Credit (₹)") { e in
                        Text(Currency.formatPaise(e.creditPaise)).monospacedDigit()
                    }
                    TableColumn("Balance (₹)") { e in
                        Text(Currency.formatPaise(e.balancePaise)).monospacedDigit()
                    }
                }
                Text("Opening: \(Currency.formatPaise(l.openingBalancePaise))")
                    .monospacedDigit()
                Text("Closing: \(Currency.formatPaise(l.closingBalancePaise))")
                    .monospacedDigit()
                    .bold()
            }
        } else { Text("Select an account.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var outstandingSection: some View {
        if let o = vm.outstanding {
            Table(o.rows) {
                TableColumn("Account", value: \.partyName)
                TableColumn("Amount (₹)") { r in
                    Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                }
            }
            Text("Total: \(Currency.formatPaise(o.totalPaise))").monospacedDigit().bold()
        } else { Text("No data.").foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private var stockValuationSection: some View {
        if let s = vm.stockValuation {
            Table(s.rows) {
                TableColumn("Item", value: \.itemName)
                TableColumn("Qty", value: \.itemCode)
                TableColumn("Quantity") { r in
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
}
