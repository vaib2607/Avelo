import SwiftUI

public struct ErrorBannerHost: View {

    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        VStack(spacing: 4) {
            if let banner = env.banner {
                ErrorBanner(kind: banner.kind) {
                    env.clearBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if env.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(busyLabel)
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

    /// AVL-P0-015: a large schema upgrade shows "(2 of 5)" instead of an
    /// indeterminate spinner, so a long migration doesn't look hung.
    private var busyLabel: String {
        if let progress = env.migrationProgress {
            return "Migrating database… (\(progress.completed) of \(progress.total))"
        }
        return "Working…"
    }
}
