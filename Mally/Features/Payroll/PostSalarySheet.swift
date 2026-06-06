import SwiftUI

public struct PostSalarySheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    let employeeId: PayrollEmployee.ID

    @State private var monthYear: Int = Calendar.current.component(.year, from: Date()) * 100
        + Calendar.current.component(.month, from: Date())
    @State private var workingDays: String = "26"
    @State private var paidDays: String = "26"
    @State private var overtime: String = "0.00"
    @State private var deductions: String = "0.00"
    @State private var canSave: Bool = false

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
                TextField("Working days", text: $workingDays)
                TextField("Paid days", text: $paidDays)
                MoneyTextField(label: "Overtime", text: $overtime)
                MoneyTextField(label: "Deductions", text: $deductions)
            }
            .formStyle(.grouped)
            .onChange(of: paidDays) { _, _ in refresh() }
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
        let wd = Int(workingDays) ?? 0
        let pd = Int(paidDays) ?? 0
        canSave = wd > 0 && pd > 0 && pd <= wd
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
        do {
            _ = try PayrollService(db: ctx.database, companyId: ctx.companyId).postEntry(
                employeeId: employeeId, monthYear: monthYear,
                workingDays: Int(workingDays) ?? 0, paidDays: Int(paidDays) ?? 0,
                overtimePaise: Currency.parseRupeeInput(overtime) ?? 0,
                deductionsPaise: Currency.parseRupeeInput(deductions) ?? 0,
                financialYearId: ctx.financialYear.id
            )
            env.markAccountTreeDirty()
            env.showSuccess("Salary posted.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
