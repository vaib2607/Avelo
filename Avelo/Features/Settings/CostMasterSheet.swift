import SwiftUI

public enum CostMasterKind: String, Sendable {
    case costCentre
    case costCategory

    var title: String {
        switch self {
        case .costCentre: return "Cost Centre"
        case .costCategory: return "Cost Category"
        }
    }
}

public struct CostMasterSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    let kind: CostMasterKind
    let existingCentre: CostCentre?
    let existingCategory: CostCategory?
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var canSave: Bool = false

    public init(kind: CostMasterKind, existingCentre: CostCentre? = nil, existingCategory: CostCategory? = nil) {
        self.kind = kind
        self.existingCentre = existingCentre
        self.existingCategory = existingCategory
        _code = State(initialValue: existingCentre?.code ?? existingCategory?.code ?? "")
        _name = State(initialValue: existingCentre?.name ?? existingCategory?.name ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(existingCentre != nil || existingCategory != nil ? "Edit \(kind.title)" : "New \(kind.title)")
                    .font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Code *", text: $code)
                TextField("Name *", text: $name)
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 420, minHeight: 240)
        .onAppear { refresh() }
    }

    private func refresh() {
        canSave = !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = MasterDataService(db: ctx.database, companyId: ctx.companyId)
            switch kind {
            case .costCentre:
                if let existingCentre {
                    var updated = existingCentre
                    updated.code = code
                    updated.name = name
                    try svc.updateCostCentre(updated)
                } else {
                    _ = try svc.createCostCentre(code: code, name: name)
                }
            case .costCategory:
                if let existingCategory {
                    var updated = existingCategory
                    updated.code = code
                    updated.name = name
                    try svc.updateCostCategory(updated)
                } else {
                    _ = try svc.createCostCategory(code: code, name: name)
                }
            }
            env.showSuccess("\(kind.title) saved.")
            env.notifyDataChanged()
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
