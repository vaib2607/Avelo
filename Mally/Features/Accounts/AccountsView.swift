import SwiftUI

public struct AccountsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: AccountsViewModel?

    public init() {}

    public var body: some View {
        AccountsContent(vm: vm)
            .navigationTitle("Accounts")
            .toolbar { toolbar }
            .task(id: reloadKey) { setupIfNeeded() }
    }

    private var reloadKey: String {
        let company = env.companyContext?.companyId.uuidString ?? "none"
        return "\(company)-\(env.dataRevision)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                env.router.present(.newAccount)
            } label: {
                Label("New Account", systemImage: "plus")
            }
        }
    }

    private func setupIfNeeded() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = AccountsViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
    }
}

@MainActor
private struct AccountsContent: View {
    let vm: AccountsViewModel?

    var body: some View {
        if let vm {
            AccountsBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct AccountsBody: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: AccountsViewModel

    var body: some View {
        HSplitView {
            groupsList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            accountsList
                .frame(minWidth: 520)
        }
    }

    @ViewBuilder
    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Groups")
                .font(.headline)
                .padding(12)
            List(selection: $vm.selectedGroupId) {
                Section {
                    Button {
                        vm.selectedGroupId = nil
                    } label: {
                        HStack {
                            Text("All groups")
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("Groups") {
                    ForEach(vm.groups) { g in
                        HStack {
                            Text(g.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { vm.selectedGroupId = g.id }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search accounts")
                Toggle("Show disabled", isOn: $vm.showDisabled)
                    .toggleStyle(.switch)
                Spacer()
            }
            .padding(12)
            List(vm.filtered) { account in
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name).font(.headline)
                        Text(account.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.formatPaise(account.openingBalancePaise)).monospacedDigit()
                    Button {
                        env.router.present(.editAccount(account.id))
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        env.router.openLedger(account.id)
                    } label: {
                        Label("Ledger", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .help("Open this account's ledger")
                    if account.isActive {
                        Button {
                            vm.disable(account.id)
                            env.markAccountTreeDirty()
                            env.notifyDataChanged()
                        } label: {
                            Label("Disable", systemImage: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .contentShape(Rectangle())
            }
        }
    }
}
