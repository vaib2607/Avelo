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
    @State private var mailingName: String = ""
    @State private var mailingAddress: String = ""
    @State private var stateCode: String = ""
    @State private var country: String = "India"
    @State private var registrationType: GSTRegistrationType?
    @State private var maintainBillwise: Bool = false
    @State private var creditPeriod: String = ""
    @State private var groups: [AccountGroup] = []
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
                Section {
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
                }
                Section("Mailing Details") {
                    TextField("Mailing name", text: $mailingName)
                    TextField("Address", text: $mailingAddress, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("State", selection: $stateCode) {
                        Text("—").tag("")
                        ForEach(GSTStateCode.table.sorted(by: { $0.value < $1.value }), id: \.key) { code, name in
                            Text("\(name) (\(code))").tag(code)
                        }
                    }
                    TextField("Country", text: $country)
                }
                Section("Statutory") {
                    Picker("GST registration type", selection: $registrationType) {
                        Text("—").tag(GSTRegistrationType?.none)
                        ForEach(GSTRegistrationType.allCases) { t in
                            Text(t.displayName).tag(Optional(t))
                        }
                    }
                    TextField("GSTIN (optional)", text: $gstin)
                        .textCase(.uppercase)
                }
                Section("Billing") {
                    Toggle("Maintain balances bill-by-bill", isOn: $maintainBillwise)
                    TextField("Default credit period (days)", text: $creditPeriod)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                // Not gated on `canSave` — see NewVoucherSheet.bottomBar for
                // why a validation-disabled button must still respond.
                Button("Save") { attemptSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
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
                mailingName = account.mailingName ?? ""
                mailingAddress = account.mailingAddress ?? ""
                stateCode = account.stateCode ?? ""
                country = account.country ?? "India"
                registrationType = account.gstRegistrationType
                maintainBillwise = account.maintainBillwise ?? false
                creditPeriod = account.creditPeriodDays.map(String.init) ?? ""
            }
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func makeInput() -> AccountInputValidator.Input {
        AccountInputValidator.Input(
            code: code, name: name, groupId: groupId,
            openingBalancePaise: Currency.parseRupeeInput(opening) ?? 0,
            openingBalanceSide: openingSide,
            gstin: gstin,
            mailingName: mailingName.isEmpty ? nil : mailingName,
            mailingAddress: mailingAddress.isEmpty ? nil : mailingAddress,
            stateCode: stateCode.isEmpty ? nil : stateCode,
            country: country.isEmpty ? nil : country,
            gstRegistrationType: registrationType,
            maintainBillwise: maintainBillwise,
            creditPeriodDays: creditPeriod.isEmpty ? nil : Int(creditPeriod),
            existingAccountId: existingId
        )
    }

    /// Returns validation errors for the current form, or nil if there's no
    /// open company to validate against (form disabled in that case anyway).
    private func validationErrors() -> [ValidationError]? {
        guard let ctx = env.companyContext else { return nil }
        let result = AccountInputValidator(db: ctx.database).validate(makeInput(), companyId: ctx.companyId)
        if case .invalid(let errs) = result { return errs }
        return []
    }

    /// Always responds to ⌘Return: saves if valid, otherwise surfaces the
    /// first validation error so the user knows why nothing happened.
    private func attemptSave() {
        if let first = validationErrors()?.first {
            env.showError(AppError.validation(first))
            return
        }
        save()
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        let input = makeInput()
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
                updated.mailingName = input.mailingName
                updated.mailingAddress = input.mailingAddress
                updated.stateCode = input.stateCode
                updated.country = input.country
                updated.gstRegistrationType = input.gstRegistrationType
                updated.maintainBillwise = input.maintainBillwise
                updated.creditPeriodDays = input.creditPeriodDays
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
