import SwiftUI

public struct StockMovementSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    let itemId: InventoryItem.ID

    @State private var type: InventoryItem.MovementType = .purchase
    @State private var quantity: String = "0.000"
    @State private var rate: String = "0.00"
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var canSave: Bool = false

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
                    ForEach([InventoryItem.MovementType.opening,
                             .purchase, .purchaseReturn,
                             .sale, .saleReturn,
                             .adjustmentIn, .adjustmentOut], id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Quantity", text: $quantity)
                MoneyTextField(label: "Rate (₹)", text: $rate)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            .onChange(of: quantity) { _, _ in refresh() }
            .onChange(of: rate) { _, _ in refresh() }
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
        let q = Double(quantity) ?? 0
        let r = Currency.parseRupeeInput(rate) ?? 0
        canSave = q > 0 && r >= 0
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            try InventoryService(db: ctx.database, companyId: ctx.companyId).recordMovement(
                itemId: itemId, date: date, type: type,
                quantity: Double(quantity) ?? 0,
                ratePaise: Currency.parseRupeeInput(rate) ?? 0,
                notes: notes.isEmpty ? nil : notes
            )
            env.showSuccess("Movement recorded.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
