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
<<<<<<< HEAD
                AppActionRegistry.perform(.accountCreate, router: env.router)
=======
                env.router.present(.newAccount)
>>>>>>> origin/main
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
<<<<<<< HEAD
                    .init(title: "Accounts", key: "⌘3"),
                    .init(title: "New account", key: "⇧⌘A")
                ],
                primaryActionTitle: "New Account",
                primaryActionSystemImage: "plus",
                primaryAction: { AppActionRegistry.perform(.accountCreate, router: env.router) }
            )
            HStack {
                Text("Groups").font(.headline)
                Spacer()
                Button { env.router.present(.newGroup) } label: {
                    Label("New Group", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
=======
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
>>>>>>> origin/main
            List(selection: $vm.selectedGroupId) {
                Section {
                    Button {
                        vm.selectedGroupId = nil
<<<<<<< HEAD
                        vm.reloadFirstPage()
=======
>>>>>>> origin/main
                    } label: {
                        HStack {
                            Text("All groups")
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("Groups") {
<<<<<<< HEAD
                    ForEach(orderedGroups, id: \.group.id) { entry in
                        HStack {
                            Text(String(repeating: "  ", count: entry.depth) + entry.group.name)
                            Spacer()
                            Button {
                                env.router.present(.editGroup(entry.group.id))
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.selectedGroupId = entry.group.id
                            vm.reloadFirstPage()
                        }
=======
                    ForEach(vm.groups) { g in
                        HStack {
                            Text(g.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { vm.selectedGroupId = g.id }
>>>>>>> origin/main
                    }
                }
            }
        }
    }

<<<<<<< HEAD
    /// Tally's List of Accounts shows groups as an indented tree (parent,
    /// then its children, depth-first), not the repository's flat
    /// sort-order listing.
    private var orderedGroups: [(group: AccountGroup, depth: Int)] {
        var byParent: [AccountGroup.ID?: [AccountGroup]] = [:]
        for g in vm.groups { byParent[g.parentGroupId, default: []].append(g) }
        var result: [(AccountGroup, Int)] = []
        func visit(_ parentId: AccountGroup.ID?, depth: Int) {
            for g in byParent[parentId] ?? [] {
                result.append((g, depth))
                visit(g.id, depth: depth + 1)
            }
        }
        visit(nil, depth: 0)
        return result
    }

=======
>>>>>>> origin/main
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
<<<<<<< HEAD
                    .onChange(of: vm.query) { _, _ in vm.reloadFirstPage() }
                Toggle("Show disabled", isOn: $vm.showDisabled)
                    .toggleStyle(.switch)
                    .onChange(of: vm.showDisabled) { _, _ in vm.reloadFirstPage() }
=======
                Toggle("Show disabled", isOn: $vm.showDisabled)
                    .toggleStyle(.switch)
>>>>>>> origin/main
                Spacer()
            }
            .padding(12)
            List(vm.filtered) { account in
                HStack {
                    VStack(alignment: .leading) {
<<<<<<< HEAD
                        Text(account.name.capitalized).font(.headline)
=======
                        Text(account.name).font(.headline)
>>>>>>> origin/main
                        Text(account.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.formatPaise(account.openingBalancePaise)).monospacedDigit()
                    Button {
<<<<<<< HEAD
                        AppActionRegistry.perform(.accountAlter, context: AppActionContext(accountId: account.id), router: env.router)
=======
                        env.router.present(.editAccount(account.id))
>>>>>>> origin/main
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button {
<<<<<<< HEAD
                        AppActionRegistry.perform(.accountDrillDown, context: AppActionContext(accountId: account.id), router: env.router)
=======
                        env.router.openLedger(account.id)
>>>>>>> origin/main
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
<<<<<<< HEAD
            PaginationControls(
                state: vm.pagination,
                isLoading: vm.isLoading,
                previous: { vm.previousPage() },
                next: { vm.nextPage() }
            )
=======
>>>>>>> origin/main
        }
    }
}
