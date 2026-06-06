import SwiftUI

public struct AccountsView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var holder = AccountsViewModelHolder()

    public init() {}

    public var body: some View {
        AccountsContent(holder: holder)
            .navigationTitle("Accounts")
            .toolbar { toolbar }
            .onAppear { setupIfNeeded() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setupIfNeeded() }
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
        guard let ctx = env.companyContext, holder.vm == nil else { return }
        holder.vm = AccountsViewModel(companyId: ctx.companyId, db: ctx.database)
    }
}

@MainActor
final class AccountsViewModelHolder: ObservableObject {
    @Published var vm: AccountsViewModel?
}

@MainActor
private struct AccountsContent: View {
    @ObservedObject var holder: AccountsViewModelHolder

    var body: some View {
        if let vm = holder.vm {
            AccountsBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct AccountsBody: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var vm: AccountsViewModel

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
                Spacer()
            }
            .padding(12)
            List(vm.accounts) { account in
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name).font(.headline)
                        Text(account.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.formatPaise(account.openingBalancePaise)).monospacedDigit()
                    Button {
                        env.router.openLedger(account.id)
                    } label: {
                        Label("Ledger", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .help("Open this account's ledger")
                }
                .contentShape(Rectangle())
            }
        }
    }
}
