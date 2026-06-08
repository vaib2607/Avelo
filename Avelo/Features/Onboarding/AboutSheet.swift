import SwiftUI

public struct AboutSheet: View {

    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Avelo").font(.title.bold())
                    Text("Offline accounting for macOS")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Version 1.0 (build 1)")
                .font(.callout)
            Text("Made locally. No network. No third-party packages. All data stays on this Mac.")
                .font(.callout)
            Spacer()
            HStack {
                Spacer()
                Button("Close") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 220)
    }
}
