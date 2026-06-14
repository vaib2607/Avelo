import SwiftUI

public struct NewEmployeeSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var designation: String = ""
    @State private var pan: String = ""
    @State private var baseSalary: String = "0.00"
    @State private var canSave: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Employee").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            ScrollView {
                Form {
                    Section("Identity") {
                        TextField("Code *", text: $code)
                        TextField("Name *", text: $name)
                        TextField("Designation", text: $designation)
                        TextField("PAN", text: $pan).textCase(.uppercase)
                    }
                    Section("Salary") {
                        MoneyTextField(label: "Base salary", text: $baseSalary)
                    }
                }
                .formStyle(.grouped)
            }
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func refresh() {
        canSave = !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            _ = try PayrollService(db: ctx.database, companyId: ctx.companyId).createEmployee(
                name: name, employeeCode: code, designation: designation.isEmpty ? nil : designation,
                pan: pan.isEmpty ? nil : pan,
                baseSalaryPaise: Currency.parseRupeeInput(baseSalary) ?? 0
            )
            env.showSuccess("Employee created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
