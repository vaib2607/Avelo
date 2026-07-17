import SwiftUI

public struct EditVoucherSheet: View {

    @Environment(AppEnvironment.self) private var env
    let voucherId: Voucher.ID
<<<<<<< HEAD
    @State private var payload: VoucherEditPayload?
    // Same fix as NewVoucherSheet: a window can only have one AppKit-level
    // sheet/alert presentation at a time, and this sheet already occupies
    // it, so RootView's root-level `.alert(item: env.globalError)` cannot
    // present while this sheet is open — errors must surface locally.
    @State private var saveError: AppError?
=======
    @State private var voucher: Voucher?
>>>>>>> origin/main

    public init(voucherId: Voucher.ID) {
        self.voucherId = voucherId
    }

    public var body: some View {
        Group {
<<<<<<< HEAD
            if let payload {
                EditVoucherEditor(payload: payload, saveError: $saveError)
=======
            if let voucher {
                EditVoucherEditor(voucher: voucher)
>>>>>>> origin/main
            } else {
                ProgressView()
            }
        }
<<<<<<< HEAD
        .frame(minWidth: 760, idealWidth: 780, minHeight: 700, idealHeight: 780)
        .task(id: env.companyContext?.companyId) { loadVoucher() }
        .alert(item: $saveError) { err in
            Alert(title: Text("Couldn't save voucher"), message: Text(err.localizedMessage), dismissButton: .default(Text("OK")))
        }
=======
        .frame(minWidth: 880, minHeight: 640)
        .task(id: env.companyContext?.companyId) { loadVoucher() }
>>>>>>> origin/main
    }

    private func loadVoucher() {
        guard let ctx = env.companyContext else {
<<<<<<< HEAD
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
=======
            voucher = nil
            return
        }
        do {
            guard let found = try VoucherService(db: ctx.database, companyId: ctx.companyId).findById(voucherId) else {
                throw AppError.notFound("Voucher")
            }
            voucher = found
        } catch {
            voucher = nil
>>>>>>> origin/main
            env.showError(AppError.wrap(error))
        }
    }
}

private struct EditVoucherEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm: VoucherEditViewModel?
<<<<<<< HEAD
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
=======
    let voucher: Voucher

    var body: some View {
        EditInner(vm: vm, voucherNumber: voucher.number, onSave: save(vm:))
>>>>>>> origin/main
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
<<<<<<< HEAD
                initialType: payload.voucher.voucherTypeCode, existingId: payload.voucher.id
            )
            let accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            model.load(accounts: accounts, initialDate: payload.voucher.date)
=======
                initialType: voucher.voucherTypeCode, existingId: voucher.id
            )
            let accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
>>>>>>> origin/main
            model.revalidate()
            vm = model
        } catch {
            vm = nil
<<<<<<< HEAD
            saveError = AppError.wrap(error)
=======
            env.showError(AppError.wrap(error))
>>>>>>> origin/main
        }
    }

    private func save(vm: VoucherEditViewModel) {
<<<<<<< HEAD
        guard let ctx = env.companyContext else {
            saveError = AppError.businessRule("No company is open — cannot save. Close this sheet, open a company, and try again.")
            return
        }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.edit(
                payload.voucher.id,
                with: vm.buildDraft(),
                in: ctx.financialYear,
                workflow: vm.buildWorkflowInputs()
            )
=======
        guard let ctx = env.companyContext else { return }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.edit(voucher.id, with: vm.buildDraft(), in: ctx.financialYear)
>>>>>>> origin/main
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            env.showSuccess("Voucher updated.")
            router.presentedSheet = nil
        } catch {
<<<<<<< HEAD
            saveError = AppError.wrap(error)
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
=======
            env.showError(AppError.wrap(error))
        }
>>>>>>> origin/main
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
        } else {
            ProgressView()
        }
    }
}

<<<<<<< HEAD
/// Same Tally-style Enter cascade as NewVoucherSheet's VoucherField, minus
/// the single-entry Account field (edit mode is always double-entry lines).
private enum EditVoucherField: Hashable {
    case date
    case party
    case narration
    case line(UUID)
    case amount(UUID)
}

=======
>>>>>>> origin/main
@MainActor
private struct EditVoucherBody: View {
    @Bindable var vm: VoucherEditViewModel
    let voucherNumber: String
    let onSave: (VoucherEditViewModel) -> Void
    @Environment(AppRouter.self) private var router
<<<<<<< HEAD
    @FocusState private var focusedField: EditVoucherField?
=======
>>>>>>> origin/main

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
<<<<<<< HEAD
            totalsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
=======
>>>>>>> origin/main
            bottomBar
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Edit Voucher \(voucherNumber)",
                subtitle: "Adjust lines, narration, or voucher metadata before saving changes back to the books.",
                hints: [
                    .init(title: "Save", key: "⌘↩"),
                    .init(title: "Cancel", key: "Esc"),
                    .init(title: "Add line", key: "⌘+")
                ]
            )
            HStack {
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
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
<<<<<<< HEAD
=======
            totalsSection
>>>>>>> origin/main
        }
        .padding(16)
    }

<<<<<<< HEAD
    private var isContra: Bool { vm.draft.voucherTypeCode == .contra }

    private var headerSection: some View {
        Form {
            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                .focused($focusedField, equals: .date)
                .onKeyPress(.return) {
                    focusedField = vm.lines.first.map { .line($0.id) }
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
            }
            HStack(alignment: .top) {
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
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
                .keyboardShortcut("r", modifiers: [.control])
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
=======
    private var headerSection: some View {
        GroupBox("Header") {
            Form {
                DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                AccountPicker(selection: $vm.partyAccountId,
                              accounts: vm.accounts,
                              placeholder: "Party (optional)")
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
        }
    }

    private var linesSection: some View {
        GroupBox("Lines") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($vm.lines) { line in
                    lineRow(line: line)
                }
                Button { vm.addLine() } label: { Label("Add line", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            .padding(8)
>>>>>>> origin/main
        }
    }

    private func lineRow(line: Binding<VoucherEditViewModel.LineRow>) -> some View {
<<<<<<< HEAD
        let lineId = line.wrappedValue.id
        return HStack {
            AccountPicker(selection: line.accountId,
                          accounts: vm.accounts,
                          onCommitSelection: { focusedField = .amount(lineId) },
                          isFocusedExternally: Binding(
                              get: { focusedField == .line(lineId) },
                              set: { if $0 { focusedField = .line(lineId) } }
                          ))
=======
        HStack {
            AccountPicker(selection: line.accountId, accounts: vm.accounts)
>>>>>>> origin/main
            Picker("", selection: line.side) {
                Text("Debit").tag(LedgerSide.debit)
                Text("Credit").tag(LedgerSide.credit)
            }
            .frame(width: 110)
            .labelsHidden()
<<<<<<< HEAD
            MoneyTextField(label: "", text: line.amount, onCommit: {
                advanceFocusAfterAmount(lineId: lineId)
            }, isFocusedExternally: Binding(
                get: { focusedField == .amount(lineId) },
                set: { if $0 { focusedField = .amount(lineId) } }
            ))
                .frame(width: 160)
            Button { vm.removeLine(lineId) } label: { Image(systemName: "minus.circle") }
=======
            MoneyTextField(label: "", text: line.amount).frame(width: 160)
            Button { vm.removeLine(line.wrappedValue.id) } label: { Image(systemName: "minus.circle") }
>>>>>>> origin/main
                .buttonStyle(.plain)
                .disabled(vm.lines.count <= 2)
        }
    }

<<<<<<< HEAD
    /// Mirrors NewVoucherSheet's advanceFocusAfterAmount — grow the grid
    /// only when this line is genuinely filled, then focus the next empty
    /// line's ledger field (or the freshly-added one).
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

    /// Always responds to the Save button/⌘Return: saves if valid, otherwise
    /// re-validates so `validationSection` below surfaces exactly what's
    /// missing instead of the button silently doing nothing.
    private func attemptSave() {
        vm.revalidate()
        guard vm.canPost else {
            if let first = vm.validationErrors.first { focus(first) }
            return
        }
        onSave(vm)
    }

    private func focus(_ error: ValidationError) {
        switch error.field {
        case "date": focusedField = .date
        case "party", "partyAccountId": focusedField = .party
        case "narration": focusedField = .narration
        default:
            if let row = vm.lines.first(where: { $0.accountId == nil }) ?? vm.lines.first {
                focusedField = row.accountId == nil ? .line(row.id) : .amount(row.id)
            }
=======
    private var validationSection: some View {
        GroupBox("Validation") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.validationErrors, id: \.code) { err in
                    Text("• \(err.message)").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
>>>>>>> origin/main
        }
    }

    private var totalsSection: some View {
<<<<<<< HEAD
        let difference = (try? CheckedMath.subtract(vm.totalDebitPaise, vm.totalCreditPaise, context: "calculating edit voucher sheet difference")) ?? 0
=======
        let difference = vm.totalDebitPaise - vm.totalCreditPaise
>>>>>>> origin/main
        return HStack {
            Spacer()
            Text("Debit: \(Currency.formatPaise(vm.totalDebitPaise))").monospacedDigit()
            Text("Credit: \(Currency.formatPaise(vm.totalCreditPaise))").monospacedDigit()
<<<<<<< HEAD
            Text(difference == 0 ? "Balanced" : "Difference: \(Currency.formatAbsolutePaise(difference))")
=======
            Text(difference == 0 ? "Balanced" : "Difference: \(Currency.formatPaise(abs(difference)))")
>>>>>>> origin/main
                .foregroundStyle(difference == 0 ? .green : .red)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
<<<<<<< HEAD
            // Not gated on `vm.canPost` — same fix as NewVoucherSheet's Post
            // button (see its comment): a disabled button swallows both the
            // click and the keyboard shortcut with zero feedback. `⌘Return`
            // instead of plain Return avoids colliding with MoneyTextField's
            // own onSubmit-adds-a-line behavior on the line grid above.
            Button("Save") { attemptSave() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
=======
            Button("Save") { onSave(vm) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canPost)
>>>>>>> origin/main
        }
        .padding(16)
    }
}
<<<<<<< HEAD

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
                Button("Close") { router.presentedSheet = nil }
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
                summaryRow("Type", payload.voucher.voucherTypeCode.rawValue)
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
=======
>>>>>>> origin/main
