import SwiftUI

public struct CloseFinancialYearSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var confirmation = CloseFinancialYearConfirmationState()
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
                if confirmation.isPresented {
                    ConfirmationDialog(
                        title: "Close financial year?",
                        message: "This marks the financial year as finished. Reports and audit history remain available, but the year cannot be reopened.",
                        confirmTitle: "Close Year",
                        isDestructive: true,
                        onConfirm: { confirmClose() },
                        onCancel: { confirmation.cancel() }
                    )
                } else {
                    Text("Closing marks this year as finished. You can still view reports and the audit log, but the year cannot be reopened.")
                }
                Text("You can close a year even when it's still unlocked, but locking first is recommended.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Close") { confirmation.requestClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 460, minHeight: 240)
    }

    private func confirmClose() {
        do {
            try confirmation.confirm {
                try run()
            }
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func run() throws {
        guard let ctx = env.companyContext else { return }
        try FinancialYearService(db: ctx.database, companyId: ctx.companyId).close(fyId)
        env.notifyDataChanged()
        env.showSuccess("Financial year closed.")
        router.presentedSheet = nil
    }
}

public struct CloseFinancialYearConfirmationState: Sendable, Equatable {
    public private(set) var isPresented: Bool = false

    public init() {}

    public mutating func requestClose() {
        isPresented = true
    }

    public mutating func cancel() {
        isPresented = false
    }

    public mutating func confirm(_ action: () throws -> Void) rethrows {
        isPresented = false
        try action()
    }
}
