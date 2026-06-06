import SwiftUI

public struct NewAccountSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var groupId: AccountGroup.ID?
    @State private var opening: String = "0.00"
    @State private var gstin: String = ""
    @State private var groups: [AccountGroup] = []
    @State private var canSave: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Account").font(.title2.bold())
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
                Picker("Group *", selection: $groupId) {
                    Text("—").tag(AccountGroup.ID?.none)
                    ForEach(leafGroups) { g in
                        Text("\(g.code) — \(g.name)").tag(Optional(g.id))
                    }
                }
                MoneyTextField(label: "Opening balance", text: $opening)
                TextField("GSTIN (optional)", text: $gstin)
                    .textCase(.uppercase)
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            .onChange(of: groupId) { _, _ in refresh() }
            .onChange(of: opening) { _, _ in refresh() }
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
        .frame(minWidth: 520, minHeight: 460)
        .task { loadGroups() }
    }

    private var leafGroups: [AccountGroup] {
        groups.filter { g in
            !groups.contains(where: { $0.parentGroupId == g.id })
        }
    }

    private func loadGroups() {
        guard let ctx = env.companyContext else { return }
        groups = (try? AccountService(db: ctx.database, companyId: ctx.companyId).listGroups()) ?? []
    }

    private func refresh() {
        let paise = Currency.parseRupeeInput(opening) ?? 0
        let input = AccountInputValidator.Input(
            code: code, name: name, groupId: groupId,
            openingBalancePaise: paise, gstin: gstin
        )
        guard let ctx = env.companyContext else { canSave = false; return }
        let result = AccountInputValidator(db: ctx.database).validate(input, companyId: ctx.companyId)
        switch result {
        case .valid: canSave = true
        case .invalid: canSave = false
        }
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        let paise = Currency.parseRupeeInput(opening) ?? 0
        let input = AccountInputValidator.Input(
            code: code, name: name, groupId: groupId,
            openingBalancePaise: paise, gstin: gstin
        )
        do {
            _ = try AccountService(db: ctx.database, companyId: ctx.companyId).createAccount(input)
            env.showSuccess("Account created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
