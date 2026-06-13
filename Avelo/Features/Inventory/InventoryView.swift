import SwiftUI

public struct InventoryView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: InventoryViewModel?
    @State private var showMovement: InventoryItem.ID?

    public init() {}

    public var body: some View {
        InventoryContent(vm: vm, showMovement: $showMovement)
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

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = InventoryViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
    }
}

private struct IdWrap: Identifiable { let id: InventoryItem.ID }

@MainActor
private struct InventoryContent: View {
    let vm: InventoryViewModel?
    @Binding var showMovement: InventoryItem.ID?

    var body: some View {
        if let vm {
            InventoryBody(vm: vm, showMovement: $showMovement)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct InventoryBody: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: InventoryViewModel
    @Binding var showMovement: InventoryItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Inventory",
                subtitle: "Stock masters, movement, and valuation in a Tally-style offline inventory workspace.",
                hints: [
                    .init(title: "Stock items", key: "⌘1"),
                    .init(title: "Movements", key: "⌘M"),
                    .init(title: "New item", key: "⇧⌘N")
                ],
                primaryActionTitle: "New Item",
                primaryActionSystemImage: "plus",
                primaryAction: { env.router.present(.newItem) }
            )
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
                    TableColumn("Group") { i in
                        Text(i.stockGroup ?? "—").foregroundStyle(i.stockGroup == nil ? .secondary : .primary)
                    }
                    TableColumn("Category") { i in
                        Text(i.stockCategory ?? "—").foregroundStyle(i.stockCategory == nil ? .secondary : .primary)
                    }
                    TableColumn("Godown") { i in
                        Text(i.godown ?? "—").foregroundStyle(i.godown == nil ? .secondary : .primary)
                    }
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
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Open Movement… to inspect item-level stock flow."),
                .init(title: "Shortcut", detail: "⌘1 switches to stock items; ⇧⌘N creates a new item."),
                .init(title: "Scope", detail: "Archived items stay visible when the toggle is on.")
            ])
        }
        .sheet(item: Binding(
            get: { showMovement.map { IdWrap(id: $0) } },
            set: { showMovement = $0?.id }
        )) { wrap in
            StockMovementSheet(itemId: wrap.id)
        }
    }
}
