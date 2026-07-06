import SwiftUI

public struct StockMovementSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let itemId: InventoryItem.ID

    @State private var type: InventoryItem.MovementType = .stockIn
    @State private var quantity: String = "0"
    @State private var selectedUnit: String = ""
    @State private var rate: String = "0.00"
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var canSave: Bool = false
    @State private var item: InventoryItem?

    public init(itemId: InventoryItem.ID) {
        self.itemId = itemId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Stock Movement").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                Picker("Type", selection: $type) {
                    ForEach(InventoryItem.MovementType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if let item {
                    Picker("Unit", selection: $selectedUnit) {
                        Text(item.unit).tag(item.unit)
                        if let alternateUnit = item.alternateUnit {
                            Text(alternateUnit).tag(alternateUnit)
                        }
                    }
                }
                TextField("Quantity", text: $quantity)
                MoneyTextField(label: "Rate (₹)", text: $rate)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            .onAppear { loadItem() }
            .onChange(of: quantity) { _, _ in refresh() }
            .onChange(of: rate) { _, _ in refresh() }
            .onChange(of: selectedUnit) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Record") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 460)
    }

    private func refresh() {
        let q = try? ExactQuantity.parse(decimal: quantity)
        let r = Currency.parseRupeeInput(rate) ?? 0
        canSave = q != nil && !(q?.isZero ?? true) && r >= 0
    }

    private func loadItem() {
        guard let ctx = env.companyContext else { return }
        item = try? InventoryService(db: ctx.database, companyId: ctx.companyId).findItem(itemId)
        selectedUnit = item?.unit ?? ""
        refresh()
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        guard let parsedQuantity = try? ExactQuantity.parse(decimal: quantity) else {
            env.showError(.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Enter a valid quantity.")))
            return
        }
        do {
            try InventoryService(db: ctx.database, companyId: ctx.companyId).recordMovement(
                itemId: itemId, date: date, type: type,
                quantity: parsedQuantity,
                ratePaise: Currency.parseRupeeInput(rate) ?? 0,
                enteredUnit: selectedUnit.isEmpty ? nil : selectedUnit,
                notes: notes.isEmpty ? nil : notes
            )
            env.showSuccess("Movement recorded.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
