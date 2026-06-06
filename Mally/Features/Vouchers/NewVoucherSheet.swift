import SwiftUI

public struct NewVoucherSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var vm: VoucherEditViewModel?
    let initialType: VoucherType.Code

    public init(initialType: VoucherType.Code) {
        self.initialType = initialType
    }

    public var body: some View {
        Group {
            if let vm = vm {
                editor(vm: vm)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 880, minHeight: 640)
        .onAppear { setup() }
    }

    @ViewBuilder
    private func editor(vm: VoucherEditViewModel) -> some View {
        VStack(spacing: 0) {
            header(vm: vm)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metaSection(vm: vm)
                    linesSection(vm: vm)
                    totalsSection(vm: vm)
                    if !vm.validationErrors.isEmpty {
                        errorList(vm: vm)
                    }
                }
                .padding(16)
            }
            Divider()
            footer(vm: vm)
        }
    }

    @ViewBuilder
    private func header(vm: VoucherEditViewModel) -> some View {
        HStack {
            Text("New \(initialType.rawValue) Voucher").font(.title2.bold())
            Spacer()
            Button { router.presentedSheet = nil } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private func metaSection(vm: VoucherEditViewModel) -> some View {
        GroupBox("Header") {
            Form {
                DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                AccountPicker(label: "Party (optional)",
                              accounts: vm.accounts,
                              selection: $vm.partyAccountId)
                TextField("Reference (optional)", text: $vm.reference)
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func linesSection(vm: VoucherEditViewModel) -> some View {
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
                ForEach($vm.lines) { $line in
                    HStack {
                        AccountPicker(label: "", accounts: vm.accounts, selection: $line.accountId)
                        Picker("", selection: $line.side) {
                            Text("Debit").tag(LedgerSide.debit)
                            Text("Credit").tag(LedgerSide.credit)
                        }
                        .frame(width: 110)
                        .labelsHidden()
                        MoneyTextField(label: "", text: $line.amount)
                            .frame(width: 160)
                        Button {
                            vm.removeLine(line.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.lines.count <= 2)
                        .frame(width: 32)
                    }
                }
                Button {
                    vm.addLine()
                } label: {
                    Label("Add line", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
        .onChange(of: vm.lines) { _, _ in vm.revalidate() }
        .onChange(of: vm.partyAccountId) { _, _ in vm.revalidate() }
        .onChange(of: vm.narration) { _, _ in vm.revalidate() }
        .onChange(of: vm.date) { _, _ in vm.revalidate() }
    }

    @ViewBuilder
    private func totalsSection(vm: VoucherEditViewModel) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Debit total: \(Currency.formatPaise(vm.totalDebitPaise))")
                Text("Credit total: \(Currency.formatPaise(vm.totalCreditPaise))")
                Text(vm.isBalanced ? "Balanced" : "Not balanced")
                    .foregroundStyle(vm.isBalanced ? .green : .red)
            }
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func errorList(vm: VoucherEditViewModel) -> some View {
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

    @ViewBuilder
    private func footer(vm: VoucherEditViewModel) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Post") { post(vm: vm) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canPost)
        }
        .padding(16)
    }

    private func setup() {
        guard let ctx = env.companyContext, vm == nil else { return }
        let model = VoucherEditViewModel(companyId: ctx.companyId, db: ctx.database,
                                         fyId: ctx.financialYear.id, initialType: initialType)
        let accounts = (try? AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()) ?? []
        model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
        model.revalidate()
        vm = model
    }

    private func post(vm: VoucherEditViewModel) {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = VoucherService(db: ctx.database, companyId: ctx.companyId)
            _ = try svc.post(draft: vm.buildDraft(), in: ctx.financialYear)
            env.showSuccess("Voucher posted.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
