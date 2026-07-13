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
    let initialType: VoucherType.Code

    public init(initialType: VoucherType.Code) {
        self.initialType = initialType
    }

    public var body: some View {
        NewVoucherEditor(vm: vm, initialType: initialType, onPost: post(vm:))
            .frame(minWidth: 880, minHeight: 640)
            .environment(router)
            .task(id: env.companyContext?.companyId) { setup() }
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
            if initialType == .sales || initialType == .purchase {
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
        guard let ctx = env.companyContext else { return }
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
            env.showError(AppError.wrap(error))
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

@MainActor
private struct NewVoucherBody: View {
    @Bindable var vm: VoucherEditViewModel
    let initialType: VoucherType.Code
    let onPost: (VoucherEditViewModel) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var submitGate = OneShotSubmitGate()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView { mainContent }
                .onChange(of: vm.lines) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.accountLedgerId) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.partyAccountId) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.billReferenceType) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.billReferenceNumber) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.narration) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.date) { _, _ in vm.revalidate(); vm.scheduleAutosave() }
                .onChange(of: vm.chequeNumber) { _, _ in vm.scheduleAutosave() }
                .onChange(of: vm.chequeDueDate) { _, _ in vm.scheduleAutosave() }
            Divider()
            bottomBar
        }
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
            if vm.itemInvoiceMode {
                itemGridSection
                if !vm.itemInvoiceValidationErrors.isEmpty { itemInvoiceValidationSection }
            } else {
                linesSection
                if !vm.validationErrors.isEmpty { validationSection }
                totalsSection
            }
        }
        .padding(16)
    }

    private var isContra: Bool { initialType == .contra }

    private var isItemInvoiceEligible: Bool {
        (initialType == .sales || initialType == .purchase) && !vm.items.isEmpty
    }

    private var itemInvoiceToggle: some View {
        Toggle("Item invoice (GST auto-calculated from item masters)", isOn: $vm.itemInvoiceMode)
            .toggleStyle(.switch)
    }

    private var itemGridSection: some View {
        GroupBox("Items") {
            VStack(alignment: .leading, spacing: 8) {
                AccountPicker(selection: $vm.salesOrPurchaseLedgerId,
                              accounts: vm.accounts,
                              placeholder: initialType == .sales ? "Sales ledger…" : "Purchase ledger…")
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
        GroupBox("Header") {
            Form {
                DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                // Tally's Contra has no party or bill reference — only fund
                // movement between cash/bank ledgers.
                if !isContra {
                    AccountPicker(selection: $vm.partyAccountId,
                                  accounts: vm.accounts,
                                  placeholder: "Party (optional)")
                    Picker("Bill reference type", selection: $vm.billReferenceType) {
                        Text("None").tag(VoucherDraft.BillReferenceType?.none)
                        ForEach(VoucherDraft.BillReferenceType.allCases) { type in
                            Text(type.rawValue).tag(Optional(type))
                        }
                    }
                    TextField("Bill reference number", text: $vm.billReferenceNumber)
                }
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
        }
    }

    /// Tally single-entry "Account" field: the cash/bank ledger this voucher
    /// moves money through (Contra: destination Dr, Payment: Cr, Receipt: Dr).
    private var accountSection: some View {
        GroupBox("Account *") {
            Form {
                AccountPicker(selection: $vm.accountLedgerId,
                              accounts: vm.accounts,
                              placeholder: isContra ? "Destination cash/bank ledger…" : "Cash/Bank ledger…",
                              filter: { vm.isCashOrBank($0) })
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
        GroupBox("Cheque (optional)") {
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
        GroupBox(vm.singleEntryMode ? "Particulars (\(vm.particularsSide == .debit ? "Dr" : "Cr"))" : "Lines") {
            VStack(alignment: .leading, spacing: 8) {
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
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
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

    private func lineRow(line: Binding<VoucherEditViewModel.LineRow>) -> some View {
        HStack {
            AccountPicker(selection: line.accountId,
                          accounts: vm.accounts,
                          filter: { particularsFilter($0) })
            if !vm.singleEntryMode {
                Picker("", selection: line.side) {
                    Text("Debit").tag(LedgerSide.debit)
                    Text("Credit").tag(LedgerSide.credit)
                }
                .frame(width: 110)
                .labelsHidden()
            }
            MoneyTextField(label: "", text: line.amount, onCommit: {
                // Only grow the grid when this line is actually filled in —
                // otherwise repeatedly pressing Enter on an already-blank
                // trailing line spams new blank rows and the voucher never
                // feels "done" (reported: entry menu seemed stuck on Enter).
                if line.wrappedValue.accountId != nil, Currency.parseRupeeInput(line.wrappedValue.amount) ?? 0 != 0 {
                    vm.addLine()
                }
            })
                .frame(width: 160)
            Button { vm.removeLine(line.wrappedValue.id) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.lines.count <= (vm.singleEntryMode ? 1 : 2))
            .frame(width: 32)
        }
    }

    private var validationSection: some View {
        GroupBox("Validation") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.validationErrors, id: \.code) { err in
                    Text("• \(err.message)").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
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
            env.showError(AppError.validation(first))
        } else {
            env.showError(AppError.businessRule("This voucher isn't ready to post yet — check the required fields above."))
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
}
