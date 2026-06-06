import SwiftUI

public struct ErrorBannerHost: View {

    @EnvironmentObject private var env: AppEnvironment

    public init() {}

    public var body: some View {
        VStack(spacing: 4) {
            if let banner = env.banner {
                ErrorBanner(kind: banner.kind, message: banner.message) {
                    env.clearBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if env.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: env.banner)
    }
}
