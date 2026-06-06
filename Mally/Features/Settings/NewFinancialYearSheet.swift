import SwiftUI

public struct NewFinancialYearSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    @State private var label: String = ""
    @State private var start: Date = IndianFinancialYear.start(for: Date().addingTimeInterval(365 * 86400))
    @State private var end: Date = IndianFinancialYear.end(for: Date().addingTimeInterval(365 * 86400))
    @State private var booksBegin: Date = IndianFinancialYear.start(for: Date().addingTimeInterval(365 * 86400))
    @State private var canSave: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Financial Year").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Label (e.g. FY 2025-26)", text: $label)
                DatePicker("Start", selection: $start, displayedComponents: .date)
                DatePicker("End", selection: $end, displayedComponents: .date)
                DatePicker("Books begin", selection: $booksBegin, displayedComponents: .date)
            }
            .formStyle(.grouped)
            .onChange(of: label) { _, _ in refresh() }
            .onChange(of: start) { _, _ in refresh() }
            .onChange(of: end) { _, _ in refresh() }
            .onChange(of: booksBegin) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 380)
    }

    private func refresh() {
        let r = FinancialYearInputValidator().validate(
            FinancialYearInputValidator.Input(label: label, startDate: start, endDate: end, booksBeginDate: booksBegin)
        )
        if case .valid = r { canSave = true } else { canSave = false }
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        do {
            _ = try FinancialYearService(db: ctx.database, companyId: ctx.companyId).create(
                label: label, startDate: start, endDate: end, booksBeginDate: booksBegin
            )
            env.showSuccess("Financial year created.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
