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
private struct ReportsBody: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: ReportsViewModel

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220)
            main
                .frame(minWidth: 540)
        }
        .safeAreaInset(edge: .bottom) {
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Select a report on the left, then drill into account or voucher rows."),
                .init(title: "Shortcut", detail: "⌘1 opens Trial Balance; ⌘6 opens Ledger."),
                .init(title: "Drill-down", detail: "Clickable rows open the related ledger or voucher.")
            ])
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
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
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading) {
            Text("Reports").font(.headline).padding(12)
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
            case .profitLoss, .gstSummary, .gstFiling, .dayBook, .ledger, .cashBook, .bankBook, .receivables, .payables, .stockMovement, .stockRegister:
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
                    ForEach(vm.accounts.filter { $0.code.uppercased().contains("CASH") || $0.code.uppercased().contains("BANK") }) { a in
                        Text("\(a.code) — \(a.name.capitalized)").tag(Optional(a.id))
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
    private var profitLossSection: some View {
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
    private var balanceSheetSection: some View {
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
        } else {
            EmptyStateView(
                title: "No GST summary yet",
                message: "GST summary needs taxable sales or purchase activity in the selected date range.",
                systemImage: "doc.text.magnifyingglass",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    @ViewBuilder
    private var gstFilingSection: some View {
        if let g = vm.gstSummary {
            VStack(alignment: .leading, spacing: 6) {
                Text("GST Filing Views").font(.headline)
                Text("Offline filing prep only; use the summary totals below to cross-check return figures.")
                    .foregroundStyle(.secondary)
                if let filingPeriod = gstFilingPeriod {
                    Text("Period: \(filingPeriod)").font(.callout)
                }
                Divider()
                row("Output taxable", g.outputTaxablePaise)
                row("Output tax", g.outputTaxPaise)
                row("Input taxable", g.inputTaxablePaise)
                row("Input tax", g.inputTaxPaise)
                Divider()
                row("IGST", g.igstPaise)
                row("CGST", g.cgstPaise)
                row("SGST", g.sgstPaise)
                row("Net payable", g.netPayablePaise, bold: true)
            }
        } else {
            EmptyStateView(
                title: "No GST filing view yet",
                message: "The filing view mirrors the GST summary for the chosen period, so it appears when GST activity exists.",
                systemImage: "doc.text.magnifyingglass",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    private var gstFilingPeriod: String? {
        guard env.companyContext != nil else { return nil }
        return "\(DateFormatters.gstReturn.string(from: vm.fromDate)) - \(DateFormatters.gstReturn.string(from: vm.toDate))"
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
            EmptyStateView(
                title: "No day book entries",
                message: "No vouchers were posted in the selected date range.",
                systemImage: "calendar.badge.clock",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            Table(rows) {
                TableColumn("Date") { r in
                    Text(DateFormatters.userDate.string(from: r.date))
                }
                TableColumn("Voucher") { r in
                    Button(r.voucherNumber) { openVoucher(r.id) }
                        .buttonStyle(.plain)
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
                        Text(l.accountName.capitalized).font(.headline)
                Table(l.entries) {
                    TableColumn("Date") { e in
                        Text(DateFormatters.userDate.string(from: e.date))
                    }
                    TableColumn("Voucher") { e in
                        Button(e.voucherNumber) { openVoucher(e.voucherId) }
                            .buttonStyle(.plain)
                    }
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
        } else {
            EmptyStateView(
                title: "No ledger selected",
                message: "Choose an account to view its ledger entries for the selected period.",
                systemImage: "book.closed",
            )
        }
    }

    @ViewBuilder
    private var receivablesSection: some View {
        outstandingList(title: "Receivables")
    }

    @ViewBuilder
    private var payablesSection: some View {
        outstandingList(title: "Payables")
    }

    @ViewBuilder
    private var stockMovementSection: some View {
        if vm.stockMovements.isEmpty {
            EmptyStateView(
                title: "No stock movements",
                message: "There were no stock movements posted in the selected period.",
                systemImage: "arrow.left.arrow.right",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Movement").font(.headline)
                Table(vm.stockMovements) {
                    TableColumn("Date") { row in
                        Text(DateFormatters.userDate.string(from: row.date))
                    }
                    TableColumn("Item") { row in
                        Text(row.itemId.uuidString.prefix(8).description)
                    }
                    TableColumn("Type", value: \.movementType.rawValue)
                    TableColumn("Qty") { row in
                        Text(String(format: "%.3f", row.quantity))
                    }
                    TableColumn("Voucher") { row in
                        if let voucherId = row.voucherId {
                            Button(row.referenceVoucherNumber ?? "Open") { openVoucher(voucherId) }
                                .buttonStyle(.plain)
                        } else {
                            Text(row.referenceVoucherNumber ?? "—")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stockRegisterSection: some View {
        if vm.stockRegisterRows.isEmpty {
            EmptyStateView(
                title: "No stock register rows",
                message: "The selected period has no item-level stock activity to list in the register.",
                systemImage: "list.bullet.rectangle",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Register").font(.headline)
                Table(vm.stockRegisterRows) {
                    TableColumn("Item") { row in
                        Text(row.itemName)
                    }
                    TableColumn("Date") { row in
                        Text(DateFormatters.userDate.string(from: row.movement.date))
                    }
                    TableColumn("Type", value: \.movement.movementType.rawValue)
                    TableColumn("Qty") { row in
                        Text(String(format: "%.3f", row.movement.quantity))
                    }
                    TableColumn("Voucher") { row in
                        if let voucherId = row.movement.voucherId {
                            Button(row.movement.referenceVoucherNumber ?? "Open") { openVoucher(voucherId) }
                                .buttonStyle(.plain)
                        } else {
                            Text(row.movement.referenceVoucherNumber ?? "—")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outstandingSection: some View {
        outstandingList(title: "Outstanding")
    }

    @ViewBuilder
    private func outstandingList(title: String) -> some View {
        if let o = vm.outstanding {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Table(o.rows) {
                    TableColumn("Account") { r in
                        Button(r.partyName.capitalized) { openLedger(r.id) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Amount (₹)") { r in
                        Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                    }
                }
                Text("Total: \(Currency.formatPaise(o.totalPaise))").monospacedDigit().bold()
            }
        } else {
            EmptyStateView(
                title: "No outstanding items",
                message: "Outstanding balances appear when receivables or payables have unpaid bill allocations.",
                systemImage: "clock.arrow.circlepath",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    @ViewBuilder
    private var stockSummarySection: some View {
        if let s = vm.stockValuation {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Summary").font(.headline)
                Table(s.rows) {
                    TableColumn("Item", value: \.itemName)
                    TableColumn("Code", value: \.itemCode)
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
            }
        } else {
            EmptyStateView(
                title: "No stock summary",
                message: "Select a different date range or stock movement mode to see stock valuation rows.",
                systemImage: "shippingbox",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    private func openLedger(_ accountId: Account.ID) {
        vm.selection = .ledger
        vm.ledgerAccountId = accountId
        vm.reload()
    }

    private func openVoucher(_ id: Voucher.ID) {
        ReportsNavigation.openVoucher(id, router: env.router)
    }
}

@MainActor
enum ReportsNavigation {
    static func openVoucher(_ voucherId: Voucher.ID, router: AppRouter) {
        router.present(.editVoucher(voucherId))
    }
}
