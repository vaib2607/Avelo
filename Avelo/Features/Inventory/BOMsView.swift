import SwiftUI

@MainActor
struct BOMsContent: View {
    let vm: BOMsViewModel?

    var body: some View {
        if let vm {
            BOMsBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct BOMsBody: View {
    @Bindable var vm: BOMsViewModel
    @State private var showNew = false
    @State private var editAssemblyItemId: InventoryItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("New BOM") { showNew = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.error != nil)
            }
            .padding(12)
            Divider()

            if let error = vm.error {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Couldn’t load BOMs",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedMessage)
                    )
                    Button("Try Again") { vm.reload() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.boms.isEmpty {
                EmptyStateView(
                    title: "No BOMs",
                    message: "Define a bill of materials to record what an assembly item is made from.",
                    systemImage: "shippingbox.and.arrow.backward",
                    actionTitle: "New BOM",
                    action: { showNew = true }
                )
            } else {
                Table(vm.boms) {
                    TableColumn("Assembly item", value: \.assemblyItemName)
                    TableColumn("Output qty") { row in
                        Text(BOMQuantityFormat.display(row.bom.outputQuantity))
                            .monospacedDigit()
                    }
                    TableColumn("Components") { row in
                        Text("\(row.componentCount)")
                            .monospacedDigit()
                    }
                    TableColumn("Status") { row in
                        if let reason = row.editingBlockReason {
                            Label("Needs attention", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help(reason)
                        } else {
                            Text("Ready")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Actions") { row in
                        if row.isEditable {
                            Button("Edit…") { editAssemblyItemId = row.bom.assemblyItemId }
                        } else {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                                .help(row.editingBlockReason ?? "This BOM cannot be edited safely.")
                        }
                    }
                }
            }
        }
        .onAppear { vm.reload() }
        .sheet(isPresented: $showNew) {
            BOMEditorSheet(assemblyItemId: nil) { vm.reload() }
        }
        .sheet(item: Binding(
            get: { editAssemblyItemId.map { IdWrap(id: $0) } },
            set: { editAssemblyItemId = $0?.id }
        )) { wrap in
            BOMEditorSheet(assemblyItemId: wrap.id) { vm.reload() }
        }
    }
}

private struct IdWrap: Identifiable {
    let id: InventoryItem.ID
}
