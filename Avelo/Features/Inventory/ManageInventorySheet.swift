import SwiftUI

public struct ManageInventorySheet: View {

    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        VStack {
            Text("Inventory Settings")
                .font(.title2.bold())
                .padding()
            Text("Per-company inventory settings are managed from the Settings tab.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
