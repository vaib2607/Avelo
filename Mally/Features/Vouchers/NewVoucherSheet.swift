import SwiftUI

public struct NewVoucherSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var holder = VoucherEditHolder()
    let initialType: VoucherType.Code

    public init(initialType: VoucherType.Code) {
        self.initialType = initialType
    }

    public var body: some View {
        NewVoucherEditor(holder: holder, initialType: initialType, onPost: post(vm:))
            .frame(minWidth: 880, minHeight: 640)
            .environmentObject(router)
            .onAppear { setup() }
    }

    private func setup() {
        guard let ctx = env.companyContext, holder.vm == nil else { return }
        let model = VoucherEditViewModel(companyId: ctx.companyId, db: ctx.database,
                                         fyId: ctx.financialYear.id, initialType: initialType)
        let accounts = (try? AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()) ?? []
        model.load(accounts: accounts, initialDate: ctx.financialYear.startDate)
        model.revalidate()
        holder.vm = model
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

@MainActor
private struct NewVoucherEditor: View {
    @ObservedObject var holder: VoucherEditHolder
    let initialType: VoucherType.Code
    let onPost: (VoucherEditViewModel) -> Void
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if let vm = holder.vm {
            NewVoucherBody(vm: vm, initialType: initialType, onPost: onPost)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct NewVoucherBody: View {
    @ObservedObject var vm: VoucherEditViewModel
    let initialType: VoucherType.Code
    let onPost: (VoucherEditViewModel) -> Void
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
            Text("New \(initialType.rawValue) Voucher").font(.title2.bold())
            Spacer()
            Button { router.presentedSheet = nil } label: {
                Image(systemName: "xmark.circle.fill")
            }
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
                TextField("Reference (optional)", text: $vm.reference)
                TextField("Narration", text: $vm.narration, axis: .vertical)
                    .lineLimit(2...4)
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
}

@MainActor
final class VoucherEditHolder: ObservableObject {
    @Published var vm: VoucherEditViewModel?
}
