import SwiftUI

/// Creates or edits the single BOM for one assembly item. Creating and editing
/// are intentionally separate service operations so an existing recipe cannot
/// be overwritten from the new-recipe flow.
public struct BOMEditorSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let assemblyItemId: InventoryItem.ID?
    let onSaved: () -> Void

    @State private var items: [InventoryItem] = []
    @State private var existingAssemblyItemIds = Set<InventoryItem.ID>()
    @State private var selectedAssemblyItemId: InventoryItem.ID?
    @State private var outputQuantity: String = "1"
    @State private var lines: [ComponentRow] = [ComponentRow()]
    @State private var loadError: AppError?
    @State private var editingBlockReason: String?

    public init(assemblyItemId: InventoryItem.ID? = nil, onSaved: @escaping () -> Void) {
        self.assemblyItemId = assemblyItemId
        self.onSaved = onSaved
    }

    struct ComponentRow: Identifiable {
        let id = UUID()
        var itemId: InventoryItem.ID?
        var quantity: String = ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(assemblyItemId == nil ? "New BOM" : "Edit BOM")
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()

            editorContent

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { load() }
    }

    @ViewBuilder
    private var editorContent: some View {
        if let loadError {
            ContentUnavailableView(
                "Couldn’t load BOM",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError.localizedMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let editingBlockReason {
            ContentUnavailableView(
                "This BOM can’t be edited",
                systemImage: "archivebox",
                description: Text(editingBlockReason)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Picker("Assembly item *", selection: $selectedAssemblyItemId) {
                    Text("Choose item…").tag(InventoryItem.ID?.none)
                    ForEach(availableAssemblyItems) { item in
                        Text("\(item.code) — \(item.name)").tag(Optional(item.id))
                    }
                }
                .disabled(assemblyItemId != nil)
                TextField("Output quantity *", text: $outputQuantity)
            }
            .formStyle(.grouped)

            GroupBox("Components") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Component item").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Qty").frame(width: 100, alignment: .leading)
                        Text("").frame(width: 32)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach($lines) { line in
                        componentRow(line: line)
                    }

                    Button { lines.append(ComponentRow()) } label: {
                        Label("Add component", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .padding(.horizontal, 16)
        }
    }

    private var availableAssemblyItems: [InventoryItem] {
        guard assemblyItemId == nil else { return items }
        return items.filter { !existingAssemblyItemIds.contains($0.id) }
    }

    private func componentRow(line: Binding<ComponentRow>) -> some View {
        let row = line.wrappedValue
        return HStack {
            Picker("", selection: line.itemId) {
                Text("Choose item…").tag(InventoryItem.ID?.none)
                ForEach(componentCandidates(for: row)) { item in
                    Text("\(item.code) — \(item.name)").tag(Optional(item.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: line.quantity)
                .frame(width: 100)

            Button { lines.removeAll { $0.id == row.id } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(lines.count <= 1)
            .frame(width: 32)
        }
    }

    private func componentCandidates(for row: ComponentRow) -> [InventoryItem] {
        let selectedByOtherRows = Set(
            lines
                .filter { $0.id != row.id }
                .compactMap(\.itemId)
        )
        return items.filter { item in
            guard item.id != selectedAssemblyItemId else { return false }
            return item.id == row.itemId || !selectedByOtherRows.contains(item.id)
        }
    }

    private var canSave: Bool {
        guard loadError == nil,
              editingBlockReason == nil,
              selectedAssemblyItemId != nil,
              let parsedOutput = try? ExactQuantity.parse(decimal: outputQuantity),
              !parsedOutput.isZero,
              !lines.isEmpty else {
            return false
        }

        let componentItemIds = lines.compactMap(\.itemId)
        guard componentItemIds.count == lines.count,
              Set(componentItemIds).count == componentItemIds.count else {
            return false
        }
        return lines.allSatisfy { line in
            guard let quantity = try? ExactQuantity.parse(decimal: line.quantity) else { return false }
            return !quantity.isZero
        }
    }

    private func load() {
        loadError = nil
        editingBlockReason = nil
        guard let ctx = env.companyContext else {
            loadError = .notFound("Company context")
            return
        }

        do {
            let inventoryRepository = InventoryRepository(db: ctx.database)
            let bomService = BOMService(db: ctx.database, companyId: ctx.companyId)
            items = try inventoryRepository.listItems(
                filter: .init(companyId: ctx.companyId, includeArchived: false, limit: 2000, offset: 0)
            )
            existingAssemblyItemIds = Set(try bomService.listBOMs().map(\.bom.assemblyItemId))

            guard let assemblyItemId else { return }
            selectedAssemblyItemId = assemblyItemId
            guard let (bom, components) = try bomService.loadBOM(for: assemblyItemId) else {
                editingBlockReason = "This BOM no longer exists. Close this sheet and create a new BOM if needed."
                return
            }
            guard let assembly = try inventoryRepository.findItem(id: assemblyItemId),
                  assembly.companyId == ctx.companyId,
                  assembly.isActive else {
                editingBlockReason = "The assembly item is archived or unavailable. Reactivate it before editing this BOM."
                return
            }

            var componentItemIds = Set<InventoryItem.ID>()
            for component in components {
                guard componentItemIds.insert(component.componentItemId).inserted else {
                    editingBlockReason = "This BOM has duplicate components and cannot be edited safely."
                    return
                }
                guard component.componentItemId != assembly.id else {
                    editingBlockReason = "This BOM contains a circular component reference and cannot be edited safely."
                    return
                }
                guard let item = try inventoryRepository.findItem(id: component.componentItemId),
                      item.companyId == ctx.companyId,
                      item.isActive else {
                    editingBlockReason = "One or more component items are archived or unavailable. Reactivate them before editing this BOM."
                    return
                }
            }

            outputQuantity = BOMQuantityFormat.display(bom.outputQuantity)
            lines = components.map {
                ComponentRow(itemId: $0.componentItemId, quantity: BOMQuantityFormat.display($0.quantity))
            }
        } catch {
            let appError = AppError.wrap(error)
            loadError = appError
            env.showError(appError)
        }
    }

    private func save() {
        guard let ctx = env.companyContext,
              let selectedAssemblyItemId else {
            return
        }
        guard let parsedOutput = try? ExactQuantity.parse(decimal: outputQuantity), !parsedOutput.isZero else {
            env.showError(.validation(.init(code: .internal, field: "outputQuantity", message: "Enter a valid output quantity greater than zero.")))
            return
        }

        do {
            let components = try lines.map { row -> BOMComponent in
                guard let itemId = row.itemId else {
                    throw AppError.validation(.init(code: .internal, field: "componentItemId", message: "Choose a component item."))
                }
                let quantity = try ExactQuantity.parse(decimal: row.quantity)
                guard !quantity.isZero else {
                    throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Component quantity must be greater than zero."))
                }
                return BOMComponent(
                    companyId: ctx.companyId,
                    bomId: UUID(),
                    componentItemId: itemId,
                    quantity: quantity
                )
            }
            guard Set(components.map(\.componentItemId)).count == components.count else {
                throw AppError.validation(.init(code: .internal, field: "componentItemId", message: "A component can only appear once."))
            }

            let service = BOMService(db: ctx.database, companyId: ctx.companyId)
            if assemblyItemId == nil {
                try service.createBOM(
                    assemblyItemId: selectedAssemblyItemId,
                    outputQuantity: parsedOutput,
                    components: components
                )
            } else {
                try service.updateBOM(
                    assemblyItemId: selectedAssemblyItemId,
                    outputQuantity: parsedOutput,
                    components: components
                )
            }
            env.showSuccess("BOM recipe saved.")
            onSaved()
            dismiss()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
