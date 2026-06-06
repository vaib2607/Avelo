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
                EditVoucherBody(voucher: voucher)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 880, minHeight: 640)
    }
}

private struct EditVoucherBody: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var vm: VoucherEditViewModel?
    let voucher: Voucher

    var body: some View {
        Group {
            if let vm = vm { inner(vm: vm) } else { ProgressView() }
        }
        .onAppear { setup() }
    }

    @ViewBuilder
    private func inner(vm: VoucherEditViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Voucher \(voucher.number)").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Header") {
                        Form {
                            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                            AccountPicker(label: "Party (optional)",
                                          accounts: vm.accounts,
                                          selection: $vm.partyAccountId)
                            TextField("Narration", text: $vm.narration, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        .formStyle(.grouped)
                    }
                    GroupBox("Lines") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach($vm.lines) { $line in
                                HStack {
                                    AccountPicker(label: "", accounts: vm.accounts, selection: $line.accountId)
                                    Picker("", selection: $line.side) {
                                        Text("Debit").tag(LedgerSide.debit)
                                        Text("Credit").tag(LedgerSide.credit)
                                    }
                                    .frame(width: 110)
                                    .labelsHidden()
                                    MoneyTextField(label: "", text: $line.amount).frame(width: 160)
                                    Button { vm.removeLine(line.id) } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain)
                                        .disabled(vm.lines.count <= 2)
                                }
                            }
                            Button { vm.addLine() } label: { Label("Add line", systemImage: "plus") }
                                .buttonStyle(.bordered)
                        }
                        .padding(8)
                    }
                    if !vm.validationErrors.isEmpty {
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
                    HStack {
                        Spacer()
                        Text("Debit: \(Currency.formatPaise(vm.totalDebitPaise))").monospacedDigit()
                        Text("Credit: \(Currency.formatPaise(vm.totalCreditPaise))").monospacedDigit()
                        Text(vm.isBalanced ? "Balanced" : "Not balanced")
                            .foregroundStyle(vm.isBalanced ? .green : .red)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.lines) { _, _ in vm.revalidate() }
            .onChange(of: vm.partyAccountId) { _, _ in vm.revalidate() }
            .onChange(of: vm.narration) { _, _ in vm.revalidate() }
            .onChange(of: vm.date) { _, _ in vm.revalidate() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { save(vm: vm) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canPost)
            }
            .padding(16)
        }
    }

    private func setup() {
        guard let ctx = env.companyContext, vm == nil else { return }
        let model = VoucherEditViewModel(
            companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id,
            initialType: voucher.voucherTypeCode, existingId: voucher.id
        )
        let accounts = (try? AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()) ?? []
        model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
        model.revalidate()
        vm = model
    }

    private func save(vm: VoucherEditViewModel) {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.edit(voucher.id, with: vm.buildDraft(), in: ctx.financialYear)
            env.showSuccess("Voucher updated.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
