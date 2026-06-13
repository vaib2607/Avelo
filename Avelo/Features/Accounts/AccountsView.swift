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
        .safeAreaInset(edge: .bottom) {
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Open a ledger or create a new account from the toolbar."),
                .init(title: "Shortcut", detail: "⌘1 shows groups and ⌘2 focuses ledgers."),
                .init(title: "Context", detail: "Group selection narrows the visible accounts.")
            ])
        }
    }

    @ViewBuilder
    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleChrome(
                title: "Accounts",
                subtitle: "Groups, ledgers, and account drill-downs with Tally-style master navigation.",
                hints: [
                    .init(title: "Groups", key: "⌘1"),
                    .init(title: "Ledgers", key: "⌘2"),
                    .init(title: "New account", key: "⇧⌘N")
                ],
                primaryActionTitle: "New Account",
                primaryActionSystemImage: "plus",
                primaryAction: { env.router.present(.newAccount) }
            )
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
                            Text(g.name.capitalized)
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
                Text("Accounts in scope")
                    .font(.headline)
                Spacer()
                Text("Edit, open ledger, or disable")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
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
                        Text(account.name.capitalized).font(.headline)
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
