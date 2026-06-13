import SwiftUI

public struct AboutSheet: View {

    @Environment(AppRouter.self) private var router

    public init() {}

    private var bundleVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(shortVersion) (build \(build))"
    }

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
            Text(bundleVersionText)
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
