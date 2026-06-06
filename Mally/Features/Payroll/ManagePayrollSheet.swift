import SwiftUI

public struct ManagePayrollSheet: View {

    @EnvironmentObject private var router: AppRouter

    public init() {}

    public var body: some View {
        VStack {
            Text("Payroll Settings")
                .font(.title2.bold())
                .padding()
            Text("Payroll settings live in Settings → Payroll.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
