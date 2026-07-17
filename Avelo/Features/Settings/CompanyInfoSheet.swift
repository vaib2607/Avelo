import SwiftUI

public struct CompanyInfoSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var company: Company
    @State private var inventoryEnabled: Bool

    public init(company: Company) {
        _company = State(initialValue: company)
        _inventoryEnabled = State(initialValue: company.isInventoryEnabled)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Company Information")
                    .font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            ScrollView {
                Form {
                    Section("Identity") {
                        TextField("Company name", text: $company.name)
                        TextField("Address line 1", text: Binding(get: { company.addressLine1 ?? "" }, set: { company.addressLine1 = $0.isEmpty ? nil : $0 }))
                        TextField("Address line 2", text: Binding(get: { company.addressLine2 ?? "" }, set: { company.addressLine2 = $0.isEmpty ? nil : $0 }))
                        TextField("City", text: Binding(get: { company.city ?? "" }, set: { company.city = $0.isEmpty ? nil : $0 }))
                        TextField("State", text: Binding(get: { company.state ?? "" }, set: { company.state = $0.isEmpty ? nil : $0 }))
                        TextField("Pincode", text: Binding(get: { company.pincode ?? "" }, set: { company.pincode = $0.isEmpty ? nil : $0 }))
                        TextField("Country", text: $company.country)
                        TextField("GSTIN", text: Binding(get: { company.gstin ?? "" }, set: { company.gstin = $0.isEmpty ? nil : $0 }))
                        TextField("PAN", text: Binding(get: { company.pan ?? "" }, set: { company.pan = $0.isEmpty ? nil : $0 }))
                        TextField("Base currency", text: $company.baseCurrency)
                    }
                    Section("Inventory") {
                        Toggle("Enable inventory", isOn: $inventoryEnabled)
                        Text("Ledger vouchers do not create stock movements automatically. Use an item invoice or record stock manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack {
                ModuleFooterBar(items: [
                    .init(title: "Next", detail: "Update company identity or inventory defaults."),
                    .init(title: "Shortcut", detail: "Return saves; Esc cancels."),
                    .init(title: "Scope", detail: "This edits only local company data.")
                ])
            }
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            var updated = company
            updated.isInventoryEnabled = inventoryEnabled
            updated.inventoryLinkMode = .manual
            try CompanyService(db: ctx.database, companyId: ctx.companyId, manager: env.manager).update(updated)
            env.notifyDataChanged()
            env.refreshCompanyFlags()
            env.showSuccess("Company information saved.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
