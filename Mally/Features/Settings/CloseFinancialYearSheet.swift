import SwiftUI

public struct CloseFinancialYearSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    let fyId: FinancialYear.ID

    public init(fyId: FinancialYear.ID) { self.fyId = fyId }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Close Financial Year").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Closing marks this year as finished. You can still view reports and the audit log, but the year cannot be reopened.")
                Text("You can close a year even when it's still unlocked, but locking first is recommended.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Close") { run() }
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
            try FinancialYearService(db: ctx.database, companyId: ctx.companyId).close(fyId)
            env.showSuccess("Financial year closed.")
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
