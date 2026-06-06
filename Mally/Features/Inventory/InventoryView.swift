import SwiftUI

public struct InventoryView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: InventoryViewModel?
    @State private var showMovement: InventoryItem.ID?

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm {
                content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem {
                Button {
                    env.router.present(.newItem)
                } label: { Label("New Item", systemImage: "plus") }
            }
        }
        .onAppear { setup() }
        .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
    }

    @ViewBuilder
    private func content(vm: InventoryViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search items…")
                Toggle("Archived", isOn: $vm.includeArchived)
                    .toggleStyle(.switch)
                    .onChange(of: vm.includeArchived) { _, _ in vm.reload() }
            }
            .padding(12)
            Divider()
            Table(vm.filtered) {
                TableColumn("Code", value: \.code)
                TableColumn("Name", value: \.name)
                TableColumn("Unit", value: \.unit)
                TableColumn("Opening Qty") { i in
                    Text(String(format: "%.3f", i.openingQuantity))
                }
                TableColumn("Opening Rate (₹)") { i in
                    Text(Currency.formatPaise(i.openingRatePaise)).monospacedDigit()
                }
                TableColumn("Status") { i in
                    StatusBadge(kind: i.isArchived ? .neutral : .success,
                                text: i.isArchived ? "Archived" : "Active")
                }
                TableColumn("Actions") { i in
                    HStack {
                        Button("Movement…") { showMovement = i.id }
                        Button("Archive") { vm.archive(i.id) }
                            .disabled(i.isArchived)
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { showMovement.map { IdWrap(id: $0) } },
            set: { showMovement = $0?.id }
        )) { wrap in
            StockMovementSheet(itemId: wrap.id)
        }
    }

    private struct IdWrap: Identifiable { let id: InventoryItem.ID }

    private func setup() {
        guard let ctx = env.companyContext else { return }
        if vm == nil || vm?.companyId != ctx.companyId {
            vm = InventoryViewModel(companyId: ctx.companyId, db: ctx.database)
            vm?.reload()
        }
    }
}
