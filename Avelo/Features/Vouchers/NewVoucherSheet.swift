import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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
            let accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
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
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.post(draft: vm.buildDraft(), in: ctx.financialYear, workflow: vm.buildWorkflowInputs())
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

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView { mainContent }
                .onChange(of: vm.lines) { _, _ in vm.revalidate() }
                .onChange(of: vm.partyAccountId) { _, _ in vm.revalidate() }
                .onChange(of: vm.billReferenceType) { _, _ in vm.revalidate() }
                .onChange(of: vm.billReferenceNumber) { _, _ in vm.revalidate() }
                .onChange(of: vm.narration) { _, _ in vm.revalidate() }
                .onChange(of: vm.date) { _, _ in vm.revalidate() }
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
                Button { router.presentedSheet = nil } label: {
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
            workflowSection
            linesSection
            if !vm.validationErrors.isEmpty { validationSection }
            totalsSection
        }
        .padding(16)
    }

    private var headerSection: some View {
        GroupBox("Header") {
            Form {
                DatePicker("Date", selection: $vm.date, displayedComponents: .date)
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
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
        }
    }

    private var workflowSection: some View {
        GroupBox("Workflow") {
            Form {
                TextField("Cheque number", text: $vm.chequeNumber)
                DatePicker("Cheque due date", selection: Binding(
                    get: { vm.chequeDueDate ?? vm.date },
                    set: { vm.chequeDueDate = $0 }
                ), displayedComponents: .date)
                TextField("TDS section code", text: $vm.tdsSectionCode)
                TextField("TDS tax amount", text: $vm.tdsTaxAmount)
                TextField("TCS section code", text: $vm.tcsSectionCode)
                TextField("TCS tax amount", text: $vm.tcsTaxAmount)
            }
            .formStyle(.grouped)
        }
    }

    private var linesSection: some View {
        GroupBox("Lines") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Side").frame(width: 110, alignment: .leading)
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

    private func lineRow(line: Binding<VoucherEditViewModel.LineRow>) -> some View {
        HStack {
            AccountPicker(selection: line.accountId, accounts: vm.accounts)
            Picker("", selection: line.side) {
                Text("Debit").tag(LedgerSide.debit)
                Text("Credit").tag(LedgerSide.credit)
            }
            .frame(width: 110)
            .labelsHidden()
            MoneyTextField(label: "", text: line.amount)
                .frame(width: 160)
            Button { vm.removeLine(line.wrappedValue.id) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.lines.count <= 2)
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
            Button("Cancel") { router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Post") { onPost(vm) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canPost)
        }
        .padding(16)
    }

    private func pasteTSV() {
        #if canImport(AppKit)
        if let text = NSPasteboard.general.string(forType: .string) {
            vm.pasteTSV(text)
        }
        #endif
    }
}
