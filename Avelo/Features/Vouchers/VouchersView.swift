import SwiftUI

public struct VouchersView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: VouchersViewModel?
    @State private var showTypeFilter: Bool = false

    public init() {}

    public var body: some View {
        VouchersContent(vm: vm, showTypeFilter: $showTypeFilter)
            .navigationTitle("Vouchers")
            .toolbar { toolbar }
            .task(id: reloadKey) { setup() }
    }

    private var reloadKey: String {
        let company = env.companyContext?.companyId.uuidString ?? "none"
        return "\(company)-\(env.dataRevision)"
    }

    static func filterDateFallback(_ date: Date?) -> Date {
        date ?? Date()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("New Journal") { env.router.present(.newJournal) }
                Button("New Payment") { env.router.present(.newPayment) }
                Button("New Receipt") { env.router.present(.newReceipt) }
                Button("New Contra")  { env.router.present(.newContra) }
                Button("New Purchase"){ env.router.present(.newPurchase) }
                Button("New Sales")   { env.router.present(.newSales) }
                Divider()
                Button("New Credit Note") { env.router.present(.newCreditNote) }
                Button("New Debit Note")  { env.router.present(.newDebitNote) }
            } label: {
                Label("New", systemImage: "plus")
            }
        }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = VouchersViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            model.reload()
            vm = model
        }
    }
}

@MainActor
private struct VouchersContent: View {
    let vm: VouchersViewModel?
    @Binding var showTypeFilter: Bool

    var body: some View {
        if let vm {
            VouchersBody(vm: vm, showTypeFilter: $showTypeFilter)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct VouchersBody: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: VouchersViewModel
    @Binding var showTypeFilter: Bool

    var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Vouchers",
                subtitle: "Keyboard-first transaction entry with voucher types, filters, and drill-down-friendly history.",
                hints: [
                    .init(title: "Contra", key: "F4"),
                    .init(title: "Payment", key: "F5"),
                    .init(title: "Receipt", key: "F6"),
                    .init(title: "Journal", key: "F7")
                ],
                primaryActionTitle: "New Sales",
                primaryActionSystemImage: "plus",
                primaryAction: { env.router.present(.newSales) }
            )
            filterBar
            Divider()
            if vm.vouchers.isEmpty {
                EmptyStateView(
                    title: vm.query.isEmpty && vm.typeFilter.isEmpty ? "No vouchers yet" : "No matching vouchers",
                    message: "Press F5 for Payment, F6 for Receipt, F7 for Journal, F4 for Contra — or use the New menu above.",
                    systemImage: "doc.text",
                    actionTitle: "New Journal",
                    action: { env.router.present(.newJournal) }
                )
            } else {
                voucherTable
            }
            PaginationControls(
                state: vm.pagination,
                isLoading: vm.isLoading,
                previous: { vm.previousPage() },
                next: { vm.nextPage() }
            )
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Use Edit or Reverse on any row to continue the workflow."),
                .init(title: "Shortcut", detail: "F4–F9 and ⌃F8/⌃F9 open the Tally voucher entry screens."),
                .init(title: "Filter", detail: "Use the Type button to narrow by voucher family.")
            ])
        }
    }

    @ViewBuilder
    private var voucherTable: some View {
        VStack(spacing: 0) {
            Table(vm.vouchers, selection: $vm.selectedVoucherId) {
                TableColumn("Date") { v in
                    Text(DateFormatters.userDate.string(from: v.date))
                }
                TableColumn("Number", value: \.number)
                TableColumn("Type", value: \.voucherTypeCode.rawValue)
                TableColumn("Party") { v in
                    if let pid = v.partyAccountId {
                        Text(vm.accountName(pid).capitalized)
                    } else { Text("—").foregroundStyle(.secondary) }
                }
                TableColumn("Narration") { v in
                    Text(v.narration).lineLimit(1).truncationMode(.tail)
                }
                TableColumn("Amount (₹)") { v in
                    Text(Currency.formatPaise(v.totalPaise))
                        .monospacedDigit()
                }
                TableColumn("Status") { v in
                    if v.isReversal {
                        StatusBadge(kind: .warning, text: "Reversal")
                    } else {
                        StatusBadge(kind: .success, text: "Posted")
                    }
                }
                TableColumn("Actions") { v in
                    HStack {
                        Button("Edit") { env.router.present(.editVoucher(v.id)) }
                            .disabled(v.isReversal)
                        Button("Reverse") { env.router.present(.reverseVoucher(v.id)) }
                            .disabled(v.isReversal)
                        // No ⌥2 keyboard shortcut here: Table has no row
                        // selection binding, so a global shortcut would be
                        // ambiguous across rows. Mouse-only until selection
                        // state is added (tracked with AVL-P1-044).
                        Button("Duplicate") { duplicate(v) }
                            .disabled(routerSheet(for: v.voucherTypeCode) == nil)
                        if v.voucherTypeCode == .sales || v.voucherTypeCode == .purchase {
                            Button("Export PDF…") { exportInvoicePDF(v) }
                        }
                    }
                }
            }
            .onKeyPress(.pageUp) { vm.selectPrevious(); return .handled }
            .onKeyPress(.pageDown) { vm.selectNext(); return .handled }
        }
        // AVL-P2-013 (Ctrl+I insert while browsing): opens a new voucher
        // without touching vm.query/typeFilter/fromDate/toDate/pagination —
        // the list's filter/scroll state is untouched because this never
        // calls reload()/reloadFirstPage().
        .background {
            Button("") { env.router.present(.newJournal) }
                .keyboardShortcut("i", modifiers: [.control])
                .hidden()
        }
    }

    /// AVL-P2-011 (Alt+2 duplicate): preloads a fresh `NewVoucherSheet` with
    /// the source voucher's lines via the same `pendingDraftRecovery` hook
    /// draft-crash-recovery uses — no new persistence path, no
    /// `avelo_voucher_drafts` row, a brand-new voucher number on save.
    private func duplicate(_ voucher: Voucher) {
        guard let ctx = env.companyContext, let sheet = routerSheet(for: voucher.voucherTypeCode) else { return }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            let lines = try svc.lines(for: voucher.id)
            env.pendingDraftRecovery = VoucherEditViewModel.duplicateDraft(from: voucher, lines: lines)
            env.router.present(sheet)
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    /// `.opening` and `.payroll` are system-generated and have no "New X"
    /// sheet to duplicate into.
    private func routerSheet(for typeCode: VoucherType.Code) -> RouterSheet? {
        switch typeCode {
        case .journal: return .newJournal
        case .payment: return .newPayment
        case .receipt: return .newReceipt
        case .contra: return .newContra
        case .purchase: return .newPurchase
        case .sales: return .newSales
        case .creditNote: return .newCreditNote
        case .debitNote: return .newDebitNote
        case .opening, .payroll: return nil
        }
    }

    private func exportInvoicePDF(_ voucher: Voucher) {
        Task {
            do {
                let data = try vm.invoicePDFData(voucherId: voucher.id)
                _ = try await NSPanelBridge.saveData(data, suggestedName: "\(voucher.number).pdf")
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search by narration / number / party…")
                    .onChange(of: vm.query) { _, _ in vm.reloadFirstPage() }
                Button { showTypeFilter.toggle() } label: {
                    Label("Type", systemImage: "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showTypeFilter) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filter by voucher type")
                            .font(.headline)
                        ForEach(VoucherType.Code.allCases) { code in
                            Toggle(code.rawValue, isOn: Binding(
                                get: { vm.typeFilter.contains(code) },
                                set: { isOn in
                                    if isOn { vm.typeFilter.insert(code) } else { vm.typeFilter.remove(code) }
                                }
                            ))
                        }
                        Divider()
                        DatePicker("From", selection: Binding(
                            get: { VouchersView.filterDateFallback(vm.fromDate) },
                            set: { vm.fromDate = $0 }
                        ), displayedComponents: .date)
                        DatePicker("To", selection: Binding(
                            get: { VouchersView.filterDateFallback(vm.toDate) },
                            set: { vm.toDate = $0 }
                        ), displayedComponents: .date)
                        Button("Clear dates") {
                            vm.fromDate = nil
                            vm.toDate = nil
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 260)
                }
                Button("Apply") { vm.reloadFirstPage() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }
}
