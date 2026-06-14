import SwiftUI

public struct PostSalarySheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let employeeId: PayrollEmployee.ID

    @State private var monthYear: Int = Calendar.current.component(.year, from: Date()) * 100
        + Calendar.current.component(.month, from: Date())
    @State private var deductions: String = "0.00"
    @State private var canSave: Bool = false
    @State private var accounts: [Account] = []
    @State private var salaryExpenseAccountId: Account.ID?
    @State private var paymentAccountId: Account.ID?

    public init(employeeId: PayrollEmployee.ID) {
        self.employeeId = employeeId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Post Salary").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                HStack {
                    Text("Salary Expense")
                    Spacer()
                    AccountPicker(selection: $salaryExpenseAccountId, accounts: accounts, placeholder: "Choose expense account…")
                        .frame(width: 260)
                }
                HStack {
                    Text("Credit Account")
                    Spacer()
                    AccountPicker(selection: $paymentAccountId, accounts: accounts, placeholder: "Choose cash, bank, or payable…")
                        .frame(width: 260)
                }
                HStack {
                    Text("Month / Year")
                    Spacer()
                    Picker("", selection: $monthYear) {
                        ForEach(generateMonthOptions(), id: \.self) { my in
                            Text(String(format: "%04d-%02d", my / 100, my % 100)).tag(my)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                MoneyTextField(label: "Deductions", text: $deductions)
            }
            .formStyle(.grouped)
            .task { loadAccounts() }
            .onChange(of: salaryExpenseAccountId) { _, _ in refresh() }
            .onChange(of: paymentAccountId) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Post") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func refresh() {
        canSave = salaryExpenseAccountId != nil && paymentAccountId != nil
    }

    private func generateMonthOptions() -> [Int] {
        let cal = Calendar.current
        let now = Date()
        var result: [Int] = []
        for offset in 0..<12 {
            if let d = cal.date(byAdding: .month, value: -offset, to: now) {
                let c = cal.dateComponents([.year, .month], from: d)
                result.append((c.year ?? 0) * 100 + (c.month ?? 0))
            }
        }
        return result
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        guard let salaryExpenseAccountId, let paymentAccountId else {
            env.showError(.businessRule("Choose the salary expense and credit accounts before posting salary."))
            return
        }
        do {
            _ = try PayrollService(db: ctx.database, companyId: ctx.companyId).postEntry(
                employeeId: employeeId, monthYear: monthYear,
                deductionsPaise: Currency.parseRupeeInput(deductions) ?? 0,
                financialYearId: ctx.financialYear.id,
                salaryExpenseAccountId: salaryExpenseAccountId,
                paymentAccountId: paymentAccountId
            )
            env.markAccountTreeDirty()
            env.showSuccess("Salary posted.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func loadAccounts() {
        guard let ctx = env.companyContext else { return }
        do {
            let loaded = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            accounts = loaded
            salaryExpenseAccountId = salaryExpenseAccountId
                ?? loaded.first(where: { $0.code == "SALARY_EXPENSE" })?.id
                ?? loaded.first(where: { $0.name.localizedCaseInsensitiveContains("salary") })?.id
            paymentAccountId = paymentAccountId
                ?? loaded.first(where: { $0.isBankAccount })?.id
                ?? loaded.first(where: { $0.code == "CASH_IN_HAND" })?.id
            refresh()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
