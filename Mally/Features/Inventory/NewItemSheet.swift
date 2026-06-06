import SwiftUI

public struct NewItemSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var unit: String = "NOS"
    @State private var openingQty: String = "0.000"
    @State private var openingRate: String = "0.00"
    @State private var gstRate: String = "0"
    @State private var hsn: String = ""
    @State private var canSave: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Item").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Code *", text: $code)
                TextField("Name *", text: $name)
                TextField("Unit", text: $unit)
                TextField("Opening quantity", text: $openingQty)
                MoneyTextField(label: "Opening rate (₹)", text: $openingRate)
                TextField("GST rate (%)", text: $gstRate)
                TextField("HSN/SAC", text: $hsn)
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private func refresh() {
        canSave = !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        let qty = Double(openingQty) ?? 0
        let rate = Currency.parseRupeeInput(openingRate) ?? 0
        let gst = Double(gstRate) ?? 0
        do {
            _ = try InventoryService(db: ctx.database, companyId: ctx.companyId).createItem(
                code: code, name: name, unit: unit,
                openingQuantity: qty, openingRatePaise: rate,
                gstRate: gst, hsnSac: hsn.isEmpty ? nil : hsn
            )
            env.showSuccess("Item created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
