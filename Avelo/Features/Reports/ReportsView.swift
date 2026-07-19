import SwiftUI

public struct ReportsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: ReportsViewModel?
    @State private var suppressNextRevisionReload = false

    public init() {}

    public var body: some View {
        ReportsContent(vm: vm)
            .navigationTitle("Reports")
            .onAppear { setup(); consumePendingLedger() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
            .onChange(of: env.companyContext?.financialYear.id) { _, _ in setup() }
            .onChange(of: env.companyContext?.isInventoryEnabled) { _, _ in enforceCapabilitySelection() }
            .onChange(of: env.dataRevision) { _, _ in
                setup()
                if suppressNextRevisionReload {
                    suppressNextRevisionReload = false
                } else {
                    vm?.reload()
                }
            }
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
            model.selectedDay = ctx.financialYear.startDate
            model.fromDate = ctx.financialYear.startDate
            model.toDate = ctx.financialYear.endDate
            model.reload()
            vm = model
        } else if vm?.fyId != ctx.financialYear.id {
            suppressNextRevisionReload = true
            vm?.resetFinancialYear(ctx.financialYear)
        }
        enforceCapabilitySelection()
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
        vm.selection = ReportSelection.permitted(
            selection,
            isInventoryEnabled: env.companyContext?.isInventoryEnabled ?? false
        )
        if selection == .ledger, vm.ledgerAccountId == nil, let first = vm.accounts.first?.id {
            vm.ledgerAccountId = first
        }
        if (selection == .cashBook || selection == .bankBook), vm.cashBankAccountId == nil {
            vm.cashBankAccountId = vm.cashBankAccounts.first?.id
        }
        vm.reload()
        env.router.pendingReportSelection = nil
    }

    private func enforceCapabilitySelection() {
        guard let vm else { return }
        let permitted = ReportSelection.permitted(
            vm.selection,
            isInventoryEnabled: env.companyContext?.isInventoryEnabled ?? false
        )
        guard vm.selection != permitted else { return }
        vm.selection = permitted
        vm.reload()
    }
}
