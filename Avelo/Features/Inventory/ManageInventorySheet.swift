import SwiftUI

public struct ManageInventorySheet: View {

    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ModuleChrome(
                title: "Inventory Settings",
                subtitle: "Per-company inventory settings are managed from the Settings tab.",
                hints: [
                    .init(title: "Open Settings", key: "↩"),
                    .init(title: "Close", key: "Esc")
                ]
            )
            Spacer(minLength: 24)
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Open Settings to change the inventory toggle or link mode."),
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
