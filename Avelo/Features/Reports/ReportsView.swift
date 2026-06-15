import SwiftUI

public struct ReportsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: ReportsViewModel?

    public init() {}

    public var body: some View {
        ReportsContent(vm: vm)
            .navigationTitle("Reports")
            .onAppear { setup(); consumePendingLedger() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
            .onChange(of: env.dataRevision) { _, _ in setup(); vm?.reload() }
            .onChange(of: env.router.pendingLedgerAccountId) { _, _ in consumePendingLedger() }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = ReportsViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            model.asOf = ctx.financialYear.endDate
            model.fromDate = ctx.financialYear.startDate
            model.toDate = ctx.financialYear.endDate
            model.reload()
            vm = model
        }
        consumePendingReportSelection()
    }

    /// Applies a deep-link request from elsewhere (e.g. AccountsView) to show a
    /// specific account's ledger, then clears the request.
    private func consumePendingLedger() {
        guard let accountId = env.router.pendingLedgerAccountId, let vm else { return }
        vm.selection = .ledger
        vm.ledgerAccountId = accountId
        vm.reload()
        env.router.pendingLedgerAccountId = nil
    }

    private func consumePendingReportSelection() {
        guard let selection = env.router.pendingReportSelection, let vm else { return }
        vm.selection = selection
        if selection == .ledger, vm.ledgerAccountId == nil, let first = vm.accounts.first?.id {
            vm.ledgerAccountId = first
        }
        if (selection == .cashBook || selection == .bankBook), vm.cashBankAccountId == nil {
            vm.cashBankAccountId = vm.accounts.first(where: { $0.code.uppercased().contains("CASH") || $0.code.uppercased().contains("BANK") })?.id
        }
        vm.reload()
        env.router.pendingReportSelection = nil
    }
}
