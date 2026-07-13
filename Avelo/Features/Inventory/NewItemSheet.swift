import SwiftUI

public struct NewItemSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var unit: String = "NOS"
    @State private var alternateUnit: String = ""
    @State private var baseUnitsPerAlternateUnit: String = ""
    @State private var valuationMethod: ValuationMethod = .fifo
    @State private var hsnCode: String = ""
    @State private var gstRate: String = ""
    @State private var gstCessRate: String = ""
    @State private var gstTaxability: GSTTaxability = .taxable
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
                TextField("Base Unit", text: $unit)
                TextField("Alternate Unit (optional)", text: $alternateUnit)
                TextField("Base Units Per Alternate Unit", text: $baseUnitsPerAlternateUnit)
                Picker("Valuation", selection: $valuationMethod) {
                    ForEach(ValuationMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                TextField("HSN code (optional)", text: $hsnCode)
                TextField("GST rate % (optional)", text: $gstRate)
                TextField("Cess rate % (optional)", text: $gstCessRate)
                Picker("GST taxability", selection: $gstTaxability) {
                    ForEach(GSTTaxability.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            .onChange(of: alternateUnit) { _, _ in refresh() }
            .onChange(of: baseUnitsPerAlternateUnit) { _, _ in refresh() }
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
        .frame(minWidth: 480, minHeight: 320)
    }

    private func refresh() {
        canSave = !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && alternateUomFieldsAreConsistent
    }

    private var alternateUomFieldsAreConsistent: Bool {
        let alt = alternateUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = baseUnitsPerAlternateUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        if alt.isEmpty && ratio.isEmpty { return true }
        if alt.isEmpty || ratio.isEmpty { return false }
        return (try? ExactQuantity.parse(decimal: ratio)) != nil
    }

    private func bps(from percentString: String) -> Int? {
        let trimmed = percentString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            let alt = alternateUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            let ratio = baseUnitsPerAlternateUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try InventoryService(db: ctx.database, companyId: ctx.companyId).createItem(
                code: code,
                name: name,
                unit: unit,
                alternateUnit: alt.isEmpty ? nil : alt,
                baseUnitsPerAlternateUnit: ratio.isEmpty ? nil : try ExactQuantity.parse(decimal: ratio),
                valuationMethod: valuationMethod,
                hsnCode: hsnCode.trimmingCharacters(in: .whitespaces).isEmpty ? nil : hsnCode.trimmingCharacters(in: .whitespaces),
                gstRateBps: bps(from: gstRate),
                gstCessRateBps: bps(from: gstCessRate),
                gstTaxability: gstTaxability
            )
            env.showSuccess("Item created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
