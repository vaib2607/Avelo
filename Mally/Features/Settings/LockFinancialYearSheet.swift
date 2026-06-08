import SwiftUI

public struct LockFinancialYearSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let fyId: FinancialYear.ID
    @State private var reason: String = ""

    public init(fyId: FinancialYear.ID) { self.fyId = fyId }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lock Financial Year").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Reason (optional)", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                Text("Locking prevents new vouchers and edits inside this year. You can unlock it later from Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Lock") { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 240)
    }

    private func run() {
        guard let ctx = env.companyContext else { return }
        do {
            try FinancialYearService(db: ctx.database, companyId: ctx.companyId)
                .lock(fyId, reason: reason.isEmpty ? nil : reason)
            env.notifyDataChanged()
            env.showSuccess("Financial year locked.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
