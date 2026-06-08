import SwiftUI

public struct NewAccountSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var groupId: AccountGroup.ID?
    @State private var opening: String = "0.00"
    @State private var openingSide: OpeningBalanceSide = .debit
    @State private var gstin: String = ""
    @State private var groups: [AccountGroup] = []
    @State private var canSave: Bool = false
    @State private var existingAccount: Account?
    private let existingId: Account.ID?

    public init(existing: Account.ID? = nil) {
        self.existingId = existing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(existingId == nil ? "New Account" : "Edit Account").font(.title2.bold())
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
                Picker("Opening side", selection: $openingSide) {
                    Text("Dr").tag(OpeningBalanceSide.debit)
                    Text("Cr").tag(OpeningBalanceSide.credit)
                }
                TextField("GSTIN (optional)", text: $gstin)
                    .textCase(.uppercase)
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            .onChange(of: groupId) { _, _ in refresh() }
            .onChange(of: opening) { _, _ in refresh() }
            .onChange(of: openingSide) { _, _ in refresh() }
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
        .task { load() }
    }

    private var leafGroups: [AccountGroup] {
        groups.filter { g in
            !groups.contains(where: { $0.parentGroupId == g.id })
        }
    }

    private func load() {
        guard let ctx = env.companyContext else { return }
        do {
            let service = AccountService(db: ctx.database, companyId: ctx.companyId)
            groups = try service.listGroups()
            if let existingId {
                guard let account = try service.findAccount(existingId) else {
                    throw AppError.notFound("Account")
                }
                existingAccount = account
                code = account.code
                name = account.name
                groupId = account.groupId
                opening = Currency.formatAmountInput(paise: account.openingBalancePaise)
                openingSide = account.openingBalanceSide
                gstin = account.gstin ?? ""
            }
        } catch {
            env.showError(AppError.wrap(error))
        }
        refresh()
    }

    private func refresh() {
        let paise = Currency.parseRupeeInput(opening) ?? 0
        let input = AccountInputValidator.Input(
            code: code, name: name, groupId: groupId,
            openingBalancePaise: paise, openingBalanceSide: openingSide,
            gstin: gstin, existingAccountId: existingId
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
            openingBalancePaise: paise, openingBalanceSide: openingSide,
            gstin: gstin, existingAccountId: existingId
        )
        do {
            let service = AccountService(db: ctx.database, companyId: ctx.companyId)
            if let existing = existingAccount {
                var updated = existing
                updated.code = input.code
                updated.name = input.name
                updated.groupId = input.groupId ?? existing.groupId
                updated.openingBalancePaise = input.openingBalancePaise
                updated.openingBalanceSide = input.openingBalanceSide
                updated.gstin = input.gstin
                updated.updatedAt = Date()
                try service.updateAccount(updated)
                env.showSuccess("Account updated.")
            } else {
                _ = try service.createAccount(input)
                env.showSuccess("Account created.")
            }
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
