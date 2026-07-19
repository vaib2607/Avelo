import SwiftUI

public struct EditVoucherSheet: View {

    @Environment(AppEnvironment.self) private var env
    let voucherId: Voucher.ID
    @State private var payload: VoucherEditPayload?
    // Same fix as NewVoucherSheet: a window can only have one AppKit-level
    // sheet/alert presentation at a time, and this sheet already occupies
    // it, so RootView's root-level `.alert(item: env.globalError)` cannot
    // present while this sheet is open — errors must surface locally.
    @State private var saveError: AppError?

    public init(voucherId: Voucher.ID) {
        self.voucherId = voucherId
    }

    public var body: some View {
        Group {
            if let payload {
                EditVoucherEditor(payload: payload, saveError: $saveError)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 760, idealWidth: 780, minHeight: 700, idealHeight: 780)
        .task(id: env.companyContext?.companyId) { loadVoucher() }
        .alert(item: $saveError) { err in
            Alert(title: Text("Couldn't save voucher"), message: Text(err.localizedMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func loadVoucher() {
        guard let ctx = env.companyContext else {
            payload = nil
            return
        }
        do {
            let service = VoucherService(db: ctx.database, companyId: ctx.companyId)
            guard let found = try service.findById(voucherId) else {
                throw AppError.notFound("Voucher")
            }
            guard let financialYear = try FinancialYearRepository(db: ctx.database).findById(found.financialYearId) else {
                throw AppError.notFound("Financial year")
            }
            let lines = try service.lines(for: voucherId)
            payload = VoucherEditPayload(voucher: found, financialYear: financialYear, lines: lines)
        } catch {
            payload = nil
            env.showError(AppError.wrap(error))
        }
    }
}

private struct EditVoucherEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm: VoucherEditViewModel?
    let payload: VoucherEditPayload
    @Binding var saveError: AppError?

    var body: some View {
        Group {
            switch VoucherCorrectionPolicy.mode(for: payload.voucher, financialYear: payload.financialYear) {
            case .editInPlace:
                EditInner(vm: vm, voucherNumber: payload.voucher.number, onSave: save(vm:))
            case .reversalOnly:
                LockedVoucherCorrectionView(payload: payload)
            }
        }
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
            let model = VoucherEditViewModel(
                companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id,
                initialType: payload.voucher.voucherTypeCode, existingId: payload.voucher.id
            )
            let accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            model.load(accounts: accounts, initialDate: payload.voucher.date)
            model.revalidate()
            model.captureCleanEditorState()
            vm = model
        } catch {
            vm = nil
            saveError = AppError.wrap(error)
        }
    }

    private func save(vm: VoucherEditViewModel) {
        guard let ctx = env.companyContext else {
            saveError = AppError.businessRule("No company is open — cannot save. Close this sheet, open a company, and try again.")
            return
        }
        switch VoucherEditorSubmission.submit(
            vm: vm,
            operation: .edit(voucherId: payload.voucher.id, financialYear: ctx.financialYear),
            db: ctx.database,
            companyId: ctx.companyId
        ) {
        case .posted:
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            env.showSuccess("Voucher updated.")
            router.completeVoucherSubmission(vm)
        case .validationFailed(let validationError):
            saveError = validationError.map(AppError.validation) ?? vm.localEditorError
        case .failed(let error):
            saveError = error
        }
    }
}

private struct VoucherEditPayload: Sendable {
    let voucher: Voucher
    let financialYear: FinancialYear
    let lines: [LedgerLine]
}

enum VoucherCorrectionPolicy {
    enum Mode: Equatable {
        case editInPlace
        case reversalOnly
    }

    static func mode(for voucher: Voucher, financialYear: FinancialYear) -> Mode {
        if financialYear.isLocked || financialYear.isClosed {
            return .reversalOnly
        }
        return .editInPlace
    }
}

@MainActor
private struct EditInner: View {
    let vm: VoucherEditViewModel?
    let voucherNumber: String
    let onSave: (VoucherEditViewModel) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let vm {
            EditVoucherBody(vm: vm, voucherNumber: voucherNumber, onSave: onSave)
                .onAppear { router.dirtyStateProvider = vm }
                .onDisappear { router.clearDirtyStateProvider(vm) }
        } else {
            ProgressView()
        }
    }
}

/// Edit mode shares the exact same focus vocabulary as create mode. It only
/// exposes the subset applicable to an editable posted voucher.
private typealias EditVoucherField = VoucherEditorFocusTarget

@MainActor
private struct EditVoucherBody: View {
    @Bindable var vm: VoucherEditViewModel
    let voucherNumber: String
    let onSave: (VoucherEditViewModel) -> Void
    @Environment(AppRouter.self) private var router
    @State private var inputCommitter = InputCommitter()
    @FocusState private var focusedField: EditVoucherField?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView { mainContent }
                .onChange(of: vm.lines) { _, _ in vm.revalidate() }
                .onChange(of: vm.partyAccountId) { _, _ in vm.revalidate() }
                .onChange(of: vm.narration) { _, _ in vm.revalidate() }
                .onChange(of: vm.date) { _, _ in vm.revalidate() }
            Divider()
            totalsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            if let error = vm.localEditorError {
                Divider()
                editorErrorPanel(error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
            bottomBar
        }
        .onKeyPress("r", phases: .down, action: handleNarrationRecallShortcut)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Edit Voucher \(voucherNumber)",
                subtitle: "Adjust lines, narration, or voucher metadata before saving changes back to the books.",
                hints: [
                    .init(title: VoucherShortcutContract.editorTitle(for: "⌘↩"), key: "⌘↩"),
                    .init(title: VoucherShortcutContract.editorTitle(for: "⌃R in Narration"), key: "⌃R"),
                    .init(title: "Cancel", key: "Esc"),
                    .init(title: "Add line", key: "⌘+")
                ]
            )
            HStack {
                Spacer()
                Button { router.dismissPresentedSheet() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            linesSection
            if !vm.validationErrors.isEmpty { validationSection }
        }
        .padding(16)
    }

    private var isContra: Bool { vm.draft.voucherTypeCode == .contra }

    private var headerSection: some View {
        Form {
            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                .focused($focusedField, equals: .date)
                .onKeyPress(.return) {
                    focusedField = vm.lines.first.map { .ledgerAccount($0.id) }
                    return .handled
                }
            if !isContra {
                AccountPicker(selection: $vm.partyAccountId,
                              accounts: vm.accounts,
                              placeholder: "Party (optional)",
                              eligibility: { vm.eligibility($0, for: .voucherParty(vm.draft.voucherTypeCode)) },
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
                    .focused($focusedField, equals: .billReferenceNumber)
            }
            HStack(alignment: .top) {
                TextEditor(text: $vm.narration)
                    .font(.body)
                    .frame(minHeight: 56, maxHeight: 112)
                    .overlay(alignment: .topLeading) {
                        if vm.narration.isEmpty {
                            Text("Narration")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Narration")
                    .focused($focusedField, equals: .narration)
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
                .onAppear { vm.loadNarrationSuggestions() }
                .help("Recall a recent narration (⌃R)")
            }
        }
        .formStyle(.grouped)
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lines")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach($vm.lines) { line in
                lineRow(line: line)
            }
            Button { vm.addLine() } label: { Label("Add line", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("+", modifiers: .command)
        }
    }

    private func lineRow(line: Binding<VoucherEditViewModel.LineRow>) -> some View {
        let lineId = line.wrappedValue.id
        return HStack {
            AccountPicker(selection: line.accountId,
                          accounts: vm.accounts,
                          onCommitSelection: { focusedField = .ledgerAmount(lineId) },
                          isFocusedExternally: Binding(
                              get: { focusedField == .ledgerAccount(lineId) },
                              set: { if $0 { focusedField = .ledgerAccount(lineId) } }
                          ))
            Picker("", selection: line.side) {
                Text("Debit").tag(LedgerSide.debit)
                Text("Credit").tag(LedgerSide.credit)
            }
            .frame(width: 110)
            .labelsHidden()
            MoneyTextField(label: "", text: line.amount, onCommit: {
                advanceFocusAfterAmount(lineId: lineId)
            }, isFocusedExternally: Binding(
                get: { focusedField == .ledgerAmount(lineId) },
                set: { if $0 { focusedField = .ledgerAmount(lineId) } }
            ), inputCommitter: inputCommitter, inputCommitterID: EditVoucherField.ledgerAmount(lineId))
                .frame(width: 160)
            Button { vm.removeLine(lineId) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .disabled(vm.lines.count <= 2)
        }
    }

    /// Mirrors NewVoucherSheet's advanceFocusAfterAmount — grow the grid
    /// only when this line is genuinely filled, then focus the next empty
    /// line's ledger field (or the freshly-added one).
    private func advanceFocusAfterAmount(lineId: UUID) {
        if let target = vm.advanceLedgerAfterCommittedAmount(lineId: lineId) {
            focusedField = .ledgerAccount(target)
        }
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vm.validationErrors, id: \.code) { err in
                Text("• \(err.message)").foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The sole edit-editor submission route. Custom control buffers must be
    /// committed before the shared feature command builds its draft.
    private func submit() {
        inputCommitter.commitAll()
        vm.clearLocalEditorError()
        onSave(vm)
        if vm.localEditorError != nil { focusedField = vm.submissionFocusTarget() }
    }

    private func handleNarrationRecallShortcut(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers == [.control], focusedField == .narration else { return .ignored }
        vm.loadNarrationSuggestions()
        if let first = vm.narrationSuggestions.first { vm.narration = first }
        return .handled
    }

    private var totalsSection: some View {
        let difference = (try? CheckedMath.subtract(vm.totalDebitPaise, vm.totalCreditPaise, context: "calculating edit voucher sheet difference")) ?? 0
        return HStack {
            Spacer()
            Text("Debit: \(Currency.formatPaise(vm.totalDebitPaise))").monospacedDigit()
            Text("Credit: \(Currency.formatPaise(vm.totalCreditPaise))").monospacedDigit()
            Text(difference == 0 ? "Balanced" : "Difference: \(Currency.formatAbsolutePaise(difference))")
                .foregroundStyle(difference == 0 ? .green : .red)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { router.dismissPresentedSheet() }.keyboardShortcut(.cancelAction)
            // Not gated on `vm.canPost` — same fix as NewVoucherSheet's Post
            // button (see its comment): a disabled button swallows both the
            // click and the keyboard shortcut with zero feedback. `⌘Return`
            // instead of plain Return avoids colliding with MoneyTextField's
            // own onSubmit-adds-a-line behavior on the line grid above.
            Button("Save") { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSubmitting)
                .accessibilityIdentifier("voucher-editor-save")
        }
        .padding(16)
    }

    private func editorErrorPanel(_ error: AppError) -> some View {
        GroupBox("Voucher not saved") {
            Text(error.localizedMessage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voucher saving error")
    }
}

private struct LockedVoucherCorrectionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let payload: VoucherEditPayload

    var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Voucher \(payload.voucher.number)",
                subtitle: "This voucher belongs to locked financial year \(payload.financialYear.label). It is read-only; corrections must be posted through a linked reversal in an open financial year.",
                hints: [
                    .init(title: "Reverse", key: "⌘R"),
                    .init(title: "Close", key: "Esc")
                ]
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    linesSection
                    correctionNotice
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { router.dismissPresentedSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Reverse…") { router.present(.reverseVoucher(payload.voucher.id)) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(payload.voucher.isReversal || payload.voucher.status == .cancelled)
            }
            .padding(16)
        }
    }

    private var summarySection: some View {
        GroupBox("Voucher") {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Date", DateFormatters.userDate.string(from: payload.voucher.date))
                summaryRow("Type", payload.voucher.voucherTypeCode.displayName)
                summaryRow("Party", payload.voucher.partyAccountId?.uuidString ?? "—")
                summaryRow("Narration", payload.voucher.narration.isEmpty ? "—" : payload.voucher.narration)
                summaryRow("Financial Year", payload.financialYear.label)
                summaryRow("Total", Currency.formatPaise(payload.voucher.totalPaise))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var linesSection: some View {
        GroupBox("Lines") {
            VStack(spacing: 8) {
                ForEach(Array(payload.lines.enumerated()), id: \.element.id) { _, line in
                    HStack {
                        Text(line.accountId.uuidString)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(line.side == .debit ? "Debit" : "Credit")
                            .frame(width: 80)
                        Text(Currency.formatPaise(line.amountPaise))
                            .monospacedDigit()
                            .frame(width: 140, alignment: .trailing)
                    }
                }
            }
            .padding(8)
        }
    }

    private var correctionNotice: some View {
        GroupBox("Correction Path") {
            Text("Use Reverse to create a linked opposite-entry voucher in the current open financial year. The locked-period voucher remains unchanged, preserving numbering and audit history.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
