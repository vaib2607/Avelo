import SwiftUI

public struct ManagePayrollSheet: View {

    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Payroll Settings",
                subtitle: "Payroll settings live in Settings → Payroll.",
                hints: [
                    .init(title: "Open Settings", key: "↩"),
                    .init(title: "Close", key: "Esc")
                ]
            )
            Spacer(minLength: 24)
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Open Settings to adjust payroll-related defaults."),
                .init(title: "Shortcut", detail: "Return opens Settings; Esc closes this sheet."),
                .init(title: "Scope", detail: "This remains local to the active company.")
            ])
            HStack {
                Button("Open Settings") {
                    router.presentedSheet = nil
                    router.go(.settings)
                }
                Button("Close") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 300)
    }
}
