import SwiftUI

public struct NewEmployeeSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var designation: String = ""
    @State private var pan: String = ""
    @State private var bankAccount: String = ""
    @State private var ifsc: String = ""
    @State private var basic: String = "0.00"
    @State private var hra: String = "0.00"
    @State private var other: String = "0.00"
    @State private var pfApplicable: Bool = true
    @State private var esiApplicable: Bool = false
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
                    Section("Bank") {
                        TextField("Account no.", text: $bankAccount)
                        TextField("IFSC", text: $ifsc).textCase(.uppercase)
                    }
                    Section("Salary components (₹)") {
                        MoneyTextField(label: "Basic", text: $basic)
                        MoneyTextField(label: "HRA", text: $hra)
                        MoneyTextField(label: "Other allowances", text: $other)
                        Toggle("PF applicable", isOn: $pfApplicable)
                        Toggle("ESI applicable", isOn: $esiApplicable)
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
        .frame(minWidth: 560, minHeight: 600)
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
                bankAccount: bankAccount.isEmpty ? nil : bankAccount,
                ifsc: ifsc.isEmpty ? nil : ifsc,
                basicPaise: Currency.parseRupeeInput(basic) ?? 0,
                hraPaise: Currency.parseRupeeInput(hra) ?? 0,
                otherAllowancesPaise: Currency.parseRupeeInput(other) ?? 0,
                pfApplicable: pfApplicable, esiApplicable: esiApplicable
            )
            env.showSuccess("Employee created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
