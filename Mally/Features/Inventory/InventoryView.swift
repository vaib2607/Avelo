import SwiftUI

public struct InventoryView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var holder = InventoryViewModelHolder()
    @State private var showMovement: InventoryItem.ID?

    public init() {}

    public var body: some View {
        InventoryContent(holder: holder, showMovement: $showMovement)
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
        guard let ctx = env.companyContext else { return }
        if holder.vm == nil || holder.vm?.companyId != ctx.companyId {
            holder.vm = InventoryViewModel(companyId: ctx.companyId, db: ctx.database)
            holder.vm?.reload()
        }
    }
}

@MainActor
final class InventoryViewModelHolder: ObservableObject {
    @Published var vm: InventoryViewModel?
}

private struct IdWrap: Identifiable { let id: InventoryItem.ID }

@MainActor
private struct InventoryContent: View {
    @ObservedObject var holder: InventoryViewModelHolder
    @Binding var showMovement: InventoryItem.ID?

    var body: some View {
        if let vm = holder.vm {
            InventoryBody(vm: vm, showMovement: $showMovement)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct InventoryBody: View {
    @ObservedObject var vm: InventoryViewModel
    @Binding var showMovement: InventoryItem.ID?

    var body: some View {
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
}
