import SwiftUI

public struct AccountsView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: AccountsViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm {
                content(vm: vm)
            } else {
                ProgressView()
            }
        }
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

    @ViewBuilder
    private func content(vm: AccountsViewModel) -> some View {
        HSplitView {
            groupsList(vm: vm)
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            accountsList(vm: vm)
                .frame(minWidth: 520)
        }
    }

    @ViewBuilder
    private func groupsList(vm: AccountsViewModel) -> some View {
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(vm.groups) { g in
                    HStack {
                        Text(g.code)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(g.name)
                        Spacer()
                    }
                    .tag(g.id as AccountGroup.ID?)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    @ViewBuilder
    private func accountsList(vm: AccountsViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search by name or code…")
                Toggle("Show disabled", isOn: $vm.showDisabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(12)
            Divider()
            Table(vm.filtered, columns: {
                TableColumn("Code", value: \.code)
                TableColumn("Name", value: \.name)
                TableColumn("Group") { acc in
                    Text(vm.groups.first(where: { $0.id == acc.groupId })?.name ?? "—")
                }
                TableColumn("Opening (₹)") { acc in
                    Text(Currency.formatPaise(acc.openingBalancePaise))
                        .monospacedDigit()
                }
                TableColumn("Status") { acc in
                    StatusBadge(kind: acc.isActive ? .success : .neutral,
                                text: acc.isActive ? "Active" : "Disabled")
                }
                TableColumn("Actions") { acc in
                    HStack {
                        Button("Disable") { vm.disable(acc.id) }
                            .disabled(!acc.isActive)
                    }
                }
            })
        }
    }

    private func setupIfNeeded() {
        guard let ctx = env.companyContext else { return }
        if vm == nil || vm?.companyId != ctx.companyId {
            vm = AccountsViewModel(companyId: ctx.companyId, db: ctx.database)
            vm?.reload()
        }
    }
}
