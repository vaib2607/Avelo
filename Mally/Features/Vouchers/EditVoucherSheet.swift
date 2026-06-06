import SwiftUI

public struct EditVoucherSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    let voucherId: Voucher.ID

    public init(voucherId: Voucher.ID) {
        self.voucherId = voucherId
    }

    public var body: some View {
        Group {
            if let ctx = env.companyContext,
               let voucher = try? VoucherService(db: ctx.database, companyId: ctx.companyId).findById(voucherId) {
                EditVoucherEditor(voucher: voucher)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 880, minHeight: 640)
    }
}

private struct EditVoucherEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var holder = VoucherEditHolder()
    let voucher: Voucher

    var body: some View {
        EditInner(holder: holder, voucherNumber: voucher.number, onSave: save(vm:))
            .environmentObject(router)
            .onAppear { setup() }
    }

    private func setup() {
        guard let ctx = env.companyContext, holder.vm == nil else { return }
        let model = VoucherEditViewModel(
            companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id,
            initialType: voucher.voucherTypeCode, existingId: voucher.id
        )
        let accounts = (try? AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()) ?? []
        model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
        model.revalidate()
        holder.vm = model
    }

    private func save(vm: VoucherEditViewModel) {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.edit(voucher.id, with: vm.buildDraft(), in: ctx.financialYear)
            env.markAccountTreeDirty()
            env.showSuccess("Voucher updated.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}

@MainActor
private struct EditInner: View {
    @ObservedObject var holder: VoucherEditHolder
    let voucherNumber: String
    let onSave: (VoucherEditViewModel) -> Void
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if let vm = holder.vm {
            EditVoucherBody(vm: vm, voucherNumber: voucherNumber, onSave: onSave)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct EditVoucherBody: View {
    @ObservedObject var vm: VoucherEditViewModel
    let voucherNumber: String
    let onSave: (VoucherEditViewModel) -> Void
    @EnvironmentObject private var router: AppRouter

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
            bottomBar
        }
    }

    private var topBar: some View {
        HStack {
            Text("Edit Voucher \(voucherNumber)").font(.title2.bold())
            Spacer()
            Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
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
            MoneyTextField(label: "", text: line.amount).frame(width: 160)
            Button { vm.removeLine(line.wrappedValue.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .disabled(vm.lines.count <= 2)
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
        HStack {
            Spacer()
            Text("Debit: \(Currency.formatPaise(vm.totalDebitPaise))").monospacedDigit()
            Text("Credit: \(Currency.formatPaise(vm.totalCreditPaise))").monospacedDigit()
            Text(vm.isBalanced ? "Balanced" : "Not balanced")
                .foregroundStyle(vm.isBalanced ? .green : .red)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
            Button("Save") { onSave(vm) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canPost)
        }
        .padding(16)
    }
}
