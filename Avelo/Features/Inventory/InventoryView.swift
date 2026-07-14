import SwiftUI

private enum InventorySection: String, CaseIterable, Identifiable {
    case items = "Items"
    case orders = "Orders"
    case boms = "BOM"
    var id: String { rawValue }
}

public struct InventoryView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: InventoryViewModel?
    @State private var ordersVM: InventoryOrdersViewModel?
    @State private var bomsVM: BOMsViewModel?
    @State private var showMovement: InventoryItem.ID?
    @State private var section: InventorySection = .items

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(InventorySection.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            switch section {
            case .items:
                InventoryContent(vm: vm, showMovement: $showMovement)
            case .orders:
                OrdersContent(vm: ordersVM)
            case .boms:
                BOMsContent(vm: bomsVM)
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem {
                switch section {
                case .items:
                    Button {
                        env.router.present(.newItem)
                    } label: { Label("New Item", systemImage: "plus") }
                case .orders, .boms:
                    EmptyView()
                }
            }
        }
        .onAppear { setup() }
        .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            ordersVM = nil
            bomsVM = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = InventoryViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
        if ordersVM == nil || ordersVM?.companyId != ctx.companyId {
            let model = InventoryOrdersViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            ordersVM = model
        }
        if bomsVM == nil || bomsVM?.companyId != ctx.companyId {
            let model = BOMsViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            bomsVM = model
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
                    .init(title: "Inventory", key: "⌘5"),
                    .init(title: "New item", key: "⇧⌘I")
                ],
                primaryActionTitle: "New Item",
                primaryActionSystemImage: "plus",
                primaryAction: { env.router.present(.newItem) }
            )
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search items…")
                    .onChange(of: vm.query) { _, _ in vm.reloadFirstPage() }
                Toggle("Archived", isOn: $vm.includeArchived)
                    .toggleStyle(.switch)
                    .onChange(of: vm.includeArchived) { _, _ in vm.reloadFirstPage() }
            }
            .padding(12)
            Divider()
                Table(vm.filtered) {
                    TableColumn("Code", value: \.code)
                    TableColumn("Name", value: \.name)
                    TableColumn("Unit", value: \.unit)
                    TableColumn("Valuation") { i in
                        Text(i.valuationMethod.displayName)
                    }
                TableColumn("Status") { i in
                    StatusBadge(kind: i.isActive ? .success : .neutral,
                                text: i.isActive ? "Active" : "Inactive")
                }
                TableColumn("Actions") { i in
                    HStack {
                        Button("Movement…") { showMovement = i.id }
                        Button("Archive") { vm.archive(i.id) }
                            .disabled(!i.isActive)
                    }
                }
            }
            PaginationControls(
                state: vm.pagination,
                isLoading: vm.isLoading,
                previous: { vm.previousPage() },
                next: { vm.nextPage() }
            )
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
