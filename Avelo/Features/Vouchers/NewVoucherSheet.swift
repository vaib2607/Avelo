import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct OneShotSubmitGate {
    private(set) var isInFlight: Bool = false

    mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    mutating func end() {
        isInFlight = false
    }
}

public struct NewVoucherSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm: VoucherEditViewModel?
    // A window can only have one AppKit-level sheet/alert presentation at a
    // time. This sheet already occupies that slot, so RootView's root-level
    // `.alert(item: env.globalError)` cannot present while this is open —
    // env.showError() silently does nothing visible until this sheet
    // closes. Post/save errors must surface locally, on this same
    // presentation, instead of routing through the app-wide error channel.
    @State private var postError: AppError?
    let initialType: VoucherType.Code

    public init(initialType: VoucherType.Code) {
        self.initialType = initialType
    }

    public var body: some View {
        NewVoucherEditor(vm: vm, initialType: initialType, onPost: post(vm:))
            .frame(minWidth: 760, idealWidth: 780, minHeight: 700, idealHeight: 780)
            .environment(router)
            .task(id: env.companyContext?.companyId) { setup() }
            .alert(item: $postError) { err in
                Alert(title: Text("Couldn't post voucher"), message: Text(err.localizedMessage), dismissButton: .default(Text("OK")))
            }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        guard vm == nil || vm?.companyId != ctx.companyId else { return }
        do {
            let model = VoucherEditViewModel(companyId: ctx.companyId, db: ctx.database,
                                             fyId: ctx.financialYear.id, initialType: initialType)
            let svc = AccountService(db: ctx.database, companyId: ctx.companyId)
            let accounts = try svc.listActiveAccounts()
            let groups = try svc.listGroups()
            // Tally: Contra/Payment/Receipt enter in single-entry mode.
            model.singleEntryMode = [.contra, .payment, .receipt].contains(initialType)
            model.load(accounts: accounts, groups: groups, initialDate: ctx.financialYear.startDate)
            if ctx.isInventoryEnabled && (initialType == .sales || initialType == .purchase) {
                model.items = (try? InventoryService(db: ctx.database, companyId: ctx.companyId).listItems()) ?? []
            }
            // Consume a pending draft recovery (AVL-P0-018) exactly once: if
            // the user chose "Resume" on the recovery prompt for this same
            // voucher type, preload the saved fields instead of starting
            // blank, then clear the pending value so it is never replayed.
            if let recovered = env.pendingDraftRecovery, recovered.voucherTypeCode == initialType {
                model.loadFromRecoveredDraft(recovered)
                env.pendingDraftRecovery = nil
            }
            model.revalidate()
            vm = model
        } catch {
            vm = nil
            env.showError(AppError.wrap(error))
        }
    }

    private func post(vm: VoucherEditViewModel) {
        guard let ctx = env.companyContext else {
            postError = AppError.businessRule("No company is open — cannot post. Close this sheet, open a company, and try again.")
            return
        }
        do {
            if vm.itemInvoiceMode, let party = vm.partyAccountId, let ledger = vm.salesOrPurchaseLedgerId {
                _ = try ItemInvoiceService(db: ctx.database, companyId: ctx.companyId).post(
                    voucherTypeCode: initialType,
                    date: vm.date,
                    partyAccountId: party,
                    salesOrPurchaseLedgerId: ledger,
                    items: vm.buildItemLineInputs(),
                    narration: vm.narration,
                    billReferenceType: vm.billReferenceType,
                    billReferenceNumber: vm.billReferenceNumber.isEmpty ? nil : vm.billReferenceNumber,
                    in: ctx.financialYear
                )
            } else {
                let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
                _ = try svc.post(draft: vm.buildDraft(), in: ctx.financialYear, workflow: vm.buildWorkflowInputs())
            }
            vm.deleteDraft()
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            env.showSuccess("Voucher posted.")
            router.presentedSheet = nil
        } catch {
            postError = AppError.wrap(error)
        }
    }
}

@MainActor
private struct NewVoucherEditor: View {
    let vm: VoucherEditViewModel?
    let initialType: VoucherType.Code
    let onPost: (VoucherEditViewModel) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let vm {
            NewVoucherBody(vm: vm, initialType: initialType, onPost: onPost)
        } else {
            ProgressView()
        }
    }
}

/// Drives the Tally-style Enter cascade: Date -> Account/first line ledger ->
/// its amount -> next blank line's ledger -> ... -> Narration.
private enum VoucherField: Hashable {
    case date
    case party
    case narration
    case accountLedger
    case line(UUID)
    case amount(UUID)
}

@MainActor
private struct NewVoucherBody: View {
    @Bindable var vm: VoucherEditViewModel
    let initialType: VoucherType.Code
    let onPost: (VoucherEditViewModel) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var submitGate = OneShotSubmitGate()
    @State private var accountCreationSheet: RouterSheet?
    @State private var accountCreationTarget: AccountCreationTarget?
    @State private var accountCreationEligibility: (Account) -> Bool = { _ in true }
    @State private var accountIDsBeforeCreation: Set<Account.ID> = []
    @State private var accountCreationRouter = AppRouter()
    @FocusState private var focusedField: VoucherField?

    var body: some View {
        editorContent
            .sheet(item: $accountCreationSheet, onDismiss: finishAccountCreation) { sheet in
                if case .newAccount = sheet {
                    NewAccountSheet().environment(accountCreationRouter)
                }
            }
            .onChange(of: accountCreationRouter.presentedSheet == nil) { _, isDismissed in
                if isDismissed { accountCreationSheet = nil }
            }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            voucherEditorScrollView
            if !vm.itemInvoiceMode {
                Divider()
                totalsSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
            bottomBar
        }
    }

    private var voucherEditorScrollView: some View {
        ScrollView { mainContent }
            .onChange(of: vm.lines) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.accountLedgerId) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.partyAccountId) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.billReferenceType) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.billReferenceNumber) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.narration) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.date) { _, _ in voucherDraftDidChange() }
            .onChange(of: vm.chequeNumber) { _, _ in voucherAutosaveDidChange() }
            .onChange(of: vm.chequeDueDate) { _, _ in voucherAutosaveDidChange() }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "New \(initialType.rawValue) Voucher",
                subtitle: "Enter lines with keyboard-first debit/credit balance feedback, then post or cancel.",
                hints: [
                    .init(title: "Save", key: "⌘↩"),
                    .init(title: "Cancel", key: "Esc"),
                    .init(title: "Add line", key: "⌘+"),
                    .init(title: "Paste TSV", key: "⌘V")
                ]
            )
            HStack {
                Spacer()
                Button("Paste TSV") { pasteTSV() }
                Button("Save Template") {
                    do {
                        try vm.saveTemplate(named: initialType.rawValue)
                    } catch {
                        env.showError(AppError.wrap(error))
                    }
                }
                Button("Load Template") {
                    do {
                        try vm.loadTemplate(named: initialType.rawValue)
                    } catch {
                        env.showError(AppError.wrap(error))
                    }
                }
                Button { vm.deleteDraft(); router.presentedSheet = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            if vm.singleEntryMode { accountSection }
            workflowSection
            if isItemInvoiceEligible { itemInvoiceToggle }
            voucherEntrySection
        }
        .padding(16)
    }

    @ViewBuilder
    private var voucherEntrySection: some View {
        if vm.itemInvoiceMode {
            itemGridSection
            if !vm.itemInvoiceValidationErrors.isEmpty { itemInvoiceValidationSection }
        } else {
            linesSection
            if !vm.validationErrors.isEmpty { validationSection }
        }
    }

    private var isContra: Bool { initialType == .contra }

    private var isItemInvoiceEligible: Bool {
        (initialType == .sales || initialType == .purchase) && !vm.items.isEmpty
    }

    private var itemInvoiceToggle: some View {
        Toggle("Item invoice (GST auto-calculated from item masters)", isOn: $vm.itemInvoiceMode)
            .toggleStyle(.switch)
            .keyboardShortcut("v", modifiers: [.control])
            .help("Toggle voucher / item-invoice mode (⌃V)")
    }

    private var itemGridSection: some View {
        GroupBox("Items") {
            VStack(alignment: .leading, spacing: 8) {
                AccountPicker(selection: $vm.salesOrPurchaseLedgerId,
                              accounts: vm.accounts,
                              placeholder: initialType == .sales ? "Sales ledger…" : "Purchase ledger…",
                              eligibility: { vm.eligibility($0, for: initialType == .sales ? .salesLedger : .purchaseLedger) },
                              onCreate: { beginAccountCreation(for: .salesOrPurchaseLedger) })
                HStack {
                    Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Qty").frame(width: 90, alignment: .leading)
                    Text("Rate (₹)").frame(width: 120, alignment: .leading)
                    Text("").frame(width: 32)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach($vm.itemLines) { line in
                    itemLineRow(line: line)
                }
                Button { vm.addItemLine() } label: {
                    Label("Add item", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
    }

    private func itemLineRow(line: Binding<VoucherEditViewModel.ItemLineRow>) -> some View {
        HStack {
            Picker("", selection: line.itemId) {
                Text("Choose item…").tag(InventoryItem.ID?.none)
                ForEach(vm.items) { item in
                    Text("\(item.code) — \(item.name)").tag(Optional(item.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: line.quantity)
                .frame(width: 90)
            MoneyTextField(label: "", text: line.rate, onCommit: {})
                .frame(width: 120)
            Button { vm.removeItemLine(line.wrappedValue.id) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.itemLines.count <= 1)
            .frame(width: 32)
        }
    }

    private var itemInvoiceValidationSection: some View {
        GroupBox("Validation") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.itemInvoiceValidationErrors, id: \.self) { message in
                    Text("• \(message)").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var headerSection: some View {
        Form {
            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                .focused($focusedField, equals: .date)
                .onKeyPress(.return) {
                    focusedField = vm.singleEntryMode ? .accountLedger : (vm.lines.first.map { .line($0.id) })
                    return .handled
                }
            // Tally's Contra has no party or bill reference — only fund
            // movement between cash/bank ledgers.
            if !isContra {
                AccountPicker(selection: $vm.partyAccountId,
                              accounts: vm.accounts,
                              placeholder: "Party (optional)",
                              eligibility: { vm.eligibility($0, for: .voucherParty(initialType)) },
                              onCreate: { beginAccountCreation(for: .party) },
                              isFocusedExternally: Binding(
                                  get: { focusedField == .party },
                                  set: { if $0 { focusedField = .party } }
                              ))
                Picker("Bill reference type", selection: $vm.billReferenceType) {
                    Text("None").tag(VoucherDraft.BillReferenceType?.none)
                    ForEach(VoucherDraft.BillReferenceType.allCases) { type in
                        Text(type.rawValue).tag(Optional(type))
                    }
                }
                TextField("Bill reference number", text: $vm.billReferenceNumber)
            }
            narrationField
        }
        .formStyle(.grouped)
    }

    private var narrationField: some View {
        HStack(alignment: .top) {
            TextField("Narration", text: $vm.narration, axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .narration)
            narrationRecallMenu
        }
    }

    private var narrationRecallMenu: some View {
        Menu {
            if vm.narrationSuggestions.isEmpty {
                Text("No recent narrations").foregroundStyle(.secondary)
            }
            ForEach(vm.narrationSuggestions, id: \.self) { suggestion in
                Button(suggestion) { vm.narration = suggestion }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("Recall a recent narration")
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .keyboardShortcut("r", modifiers: [.control])
        .onAppear { vm.loadNarrationSuggestions() }
        .help("Recall a recent narration (⌃R)")
    }

    /// Tally single-entry "Account" field: the cash/bank ledger this voucher
    /// moves money through (Contra: destination Dr, Payment: Cr, Receipt: Dr).
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Account *")
            Form {
                AccountPicker(selection: $vm.accountLedgerId,
                              accounts: vm.accounts,
                              placeholder: isContra ? "Destination cash/bank ledger…" : "Cash/Bank ledger…",
                              eligibility: { vm.eligibility($0, for: .voucherPrimaryCashBank(initialType)) },
                              onCreate: {
                                  beginAccountCreation(
                                      for: .accountLedger,
                                      eligibility: accountLedgerEligibility
                                  )
                              },
                              onCommitSelection: {
                                  if let firstLineId = vm.lines.first?.id { focusedField = .line(firstLineId) }
                              },
                              isFocusedExternally: Binding(
                                  get: { focusedField == .accountLedger },
                                  set: { if $0 { focusedField = .accountLedger } }
                              ))
                Text(vm.accountSide == .debit ? "This ledger will be debited." : "This ledger will be credited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
    }

    private var workflowSection: some View {
        // TDS/TCS and post-dated workflows are deferred (VoucherService rejects
        // them outside the frozen schema), so only cheque details are exposed.
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Cheque (optional)")
            Form {
                TextField("Cheque number", text: $vm.chequeNumber)
                DatePicker("Cheque due date", selection: Binding(
                    get: { vm.chequeDueDate ?? vm.date },
                    set: { vm.chequeDueDate = $0 }
                ), displayedComponents: .date)
            }
            .formStyle(.grouped)
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(vm.singleEntryMode ? "Particulars (\(vm.particularsSide == .debit ? "Dr" : "Cr"))" : "Lines")
            HStack {
                Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                if !vm.singleEntryMode {
                    Text("Side").frame(width: 110, alignment: .leading)
                }
                Text("Amount (₹)").frame(width: 160, alignment: .leading)
                Text("").frame(width: 32)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach($vm.lines) { line in
                lineRow(line: line)
            }
            Button { vm.addLine() } label: {
                Label("Add line", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Particulars picker filter: Contra allows only cash/bank counter-ledgers
    /// (excluding the Account ledger); Payment/Receipt exclude cash/bank —
    /// the cash/bank side lives in the Account field (Tally default; the
    /// "use payment as contra" F12 override arrives with the config system).
    private func particularsFilter(_ account: Account) -> Bool {
        guard vm.singleEntryMode else { return true }
        if isContra {
            return vm.isCashOrBank(account) && account.id != vm.accountLedgerId
        }
        return !vm.isCashOrBank(account)
    }

    private func accountLedgerEligibility(_ account: Account) -> Bool {
        vm.isCashOrBank(account)
    }

    private func lineRow(line: Binding<VoucherEditViewModel.LineRow>) -> some View {
        let lineId = line.wrappedValue.id
        return HStack {
            AccountPicker(selection: line.accountId,
                          accounts: vm.accounts,
                          eligibility: { vm.eligibility($0, for: .voucherParticular(initialType)) },
                          onCreate: {
                              beginAccountCreation(
                                  for: .line(lineId),
                                  eligibility: particularsFilter
                              )
                          },
                          onCommitSelection: { focusedField = .amount(lineId) },
                          isFocusedExternally: Binding(
                              get: { focusedField == .line(lineId) },
                              set: { if $0 { focusedField = .line(lineId) } }
                          ))
            if !vm.singleEntryMode {
                Picker("", selection: line.side) {
                    Text("Debit").tag(LedgerSide.debit)
                    Text("Credit").tag(LedgerSide.credit)
                }
                .frame(width: 110)
                .labelsHidden()
            }
            MoneyTextField(label: "", text: line.amount, onCommit: {
                advanceFocusAfterAmount(lineId: lineId)
            }, isFocusedExternally: Binding(
                get: { focusedField == .amount(lineId) },
                set: { if $0 { focusedField = .amount(lineId) } }
            ))
                .frame(width: 160)
            Button { vm.removeLine(lineId) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.lines.count <= (vm.singleEntryMode ? 1 : 2))
            .frame(width: 32)
        }
    }

    /// Enter-on-amount cascade: grow the grid only when this line is
    /// actually filled in (repeatedly pressing Enter on an already-blank
    /// trailing line must not spam new blank rows — reported: entry menu
    /// seemed stuck on Enter), then focus the next place to type: the next
    /// empty line's ledger field if one already exists, otherwise the
    /// freshly-added blank line's ledger field.
    private func advanceFocusAfterAmount(lineId: UUID) {
        guard let index = vm.lines.firstIndex(where: { $0.id == lineId }) else { return }
        let filled = vm.lines[index].accountId != nil
            && (Currency.parseRupeeInput(vm.lines[index].amount) ?? 0) != 0
        guard filled else { return }
        if let nextEmpty = vm.lines[(index + 1)...].first(where: { $0.accountId == nil }) {
            focusedField = .line(nextEmpty.id)
            return
        }
        vm.addLine()
        if let newLine = vm.lines.last { focusedField = .line(newLine.id) }
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vm.validationErrors, id: \.code) { err in
                Text("• \(err.message)").foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalsSection: some View {
        Group {
            if vm.singleEntryMode {
                // Single entry balances by construction; show the total and
                // what still blocks posting.
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total: \(Currency.formatPaise(vm.particularsTotalPaise))")
                        if vm.accountLedgerId == nil {
                            Text("Select the cash/bank account").foregroundStyle(.red)
                        } else if vm.particularsTotalPaise <= 0 {
                            Text("Enter at least one amount").foregroundStyle(.red)
                        } else {
                            Text("Balanced").foregroundStyle(.green)
                        }
                    }
                    .monospacedDigit()
                }
            } else {
                doubleEntryTotals
            }
        }
    }

    private var doubleEntryTotals: some View {
        let difference = (try? CheckedMath.subtract(vm.totalDebitPaise, vm.totalCreditPaise, context: "calculating new voucher sheet difference")) ?? 0
        return HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Debit total: \(Currency.formatPaise(vm.totalDebitPaise))")
                Text("Credit total: \(Currency.formatPaise(vm.totalCreditPaise))")
                Text(difference == 0 ? "Balanced" : "Difference: \(Currency.formatAbsolutePaise(difference))")
                    .foregroundStyle(difference == 0 ? .green : .red)
            }
            .monospacedDigit()
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { vm.deleteDraft(); router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
            // Deliberately NOT gated on `vm.canPost`: a button disabled for
            // validation reasons swallows both mouse clicks and its
            // `.keyboardShortcut(.defaultAction)` (which also collides with
            // MoneyTextField's own onSubmit on plain Return) with zero
            // feedback — this is what made voucher entry "not work" on both
            // Enter and clicking Post while a field was still missing.
            // `attemptSubmit()` always responds: posts if valid, otherwise
            // shows exactly what's missing.
            Button("Post") { attemptSubmit() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(submitGate.isInFlight)
        }
        .padding(16)
    }

    /// Always responds to ⌘Return: posts if valid, otherwise re-validates
    /// and surfaces the first error so the user knows why nothing happened.
    private func attemptSubmit() {
        guard !submitGate.isInFlight else { return }
        if vm.itemInvoiceMode {
            if vm.canPostItemInvoice {
                postOnce()
            } else {
                env.showError(AppError.businessRule(vm.itemInvoiceValidationErrors.first ?? "This voucher isn't ready to post yet."))
            }
            return
        }
        vm.revalidate()
        if vm.canPost {
            postOnce()
        } else if let first = vm.validationErrors.first {
            focus(first)
            env.showError(AppError.validation(first))
        } else {
            env.showError(AppError.businessRule("This voucher isn't ready to post yet — check the required fields above."))
        }
    }

    private func focus(_ error: ValidationError) {
        switch error.field {
        case "date": focusedField = .date
        case "party", "partyAccountId": focusedField = .party
        case "narration": focusedField = .narration
        case "accountLedgerId": focusedField = .accountLedger
        default:
            if let row = vm.lines.first(where: { $0.accountId == nil }) ?? vm.lines.first {
                focusedField = row.accountId == nil ? .line(row.id) : .amount(row.id)
            }
        }
    }

    private func postOnce() {
        guard submitGate.begin() else { return }
        defer { submitGate.end() }
        onPost(vm)
    }

    private func pasteTSV() {
        #if canImport(AppKit)
        if let text = NSPasteboard.general.string(forType: .string) {
            vm.pasteTSV(text)
        }
        #endif
    }

    private func voucherDraftDidChange() {
        vm.revalidate()
        vm.scheduleAutosave()
    }

    private func voucherAutosaveDidChange() {
        vm.scheduleAutosave()
    }

    private func beginAccountCreation(for target: AccountCreationTarget,
                                      eligibility: @escaping (Account) -> Bool = { _ in true }) {
        accountCreationTarget = target
        accountCreationEligibility = eligibility
        accountIDsBeforeCreation = Set(vm.accounts.map(\.id))
        accountCreationRouter.presentedSheet = .newAccount
        accountCreationSheet = .newAccount
    }

    private func finishAccountCreation() {
        defer { resetAccountCreationRequest() }
        guard env.companyContext != nil, let target = accountCreationTarget else { return }
        do {
            try vm.reloadAccountContext()
            let accounts = vm.accounts
            switch accountCreationSelection(
                before: accountIDsBeforeCreation,
                accounts: accounts,
                eligibility: accountCreationEligibility
            ) {
            case .selected(let createdID):
                switch target {
                case .accountLedger: vm.accountLedgerId = createdID
                case .party: vm.partyAccountId = createdID
                case .salesOrPurchaseLedger: vm.salesOrPurchaseLedgerId = createdID
                case .line(let id):
                    if let index = vm.lines.firstIndex(where: { $0.id == id }) { vm.lines[index].accountId = createdID }
                }
                vm.revalidate()
            case .rejected:
                env.showError(AppError.businessRule("The new account is not eligible for this field and was not selected."))
            case .none:
                break
            }
        } catch { env.showError(AppError.wrap(error)) }
    }

    private func resetAccountCreationRequest() {
        accountCreationTarget = nil
        accountCreationEligibility = { _ in true }
        accountIDsBeforeCreation = []
    }
}

internal enum AccountCreationTarget: Hashable {
    case accountLedger, party, salesOrPurchaseLedger
    case line(UUID)
}

internal func newlyCreatedAccountID(before: Set<Account.ID>, after: Set<Account.ID>) -> Account.ID? {
    after.subtracting(before).first
}

internal enum AccountCreationSelection: Equatable {
    case none
    case selected(Account.ID)
    case rejected(Account.ID)
}

internal func accountCreationSelection(before: Set<Account.ID>,
                                       accounts: [Account],
                                       eligibility: (Account) -> Bool) -> AccountCreationSelection {
    guard let createdID = newlyCreatedAccountID(before: before, after: Set(accounts.map(\.id))),
          let created = accounts.first(where: { $0.id == createdID }) else {
        return .none
    }
    return eligibility(created) ? .selected(created.id) : .rejected(created.id)
}
