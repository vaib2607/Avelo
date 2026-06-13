import SwiftUI

public struct ModuleChrome: View {
    public struct ShortcutHint: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let title: String
        public let key: String

        public init(title: String, key: String) {
            self.title = title
            self.key = key
        }
    }

    public let title: String
    public let subtitle: String
    public let hints: [ShortcutHint]
    public let primaryActionTitle: String?
    public let primaryActionSystemImage: String?
    public let primaryAction: (() -> Void)?

    public init(title: String,
                subtitle: String,
                hints: [ShortcutHint] = [],
                primaryActionTitle: String? = nil,
                primaryActionSystemImage: String? = nil,
                primaryAction: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.hints = hints
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionSystemImage = primaryActionSystemImage
        self.primaryAction = primaryAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let primaryActionTitle, let primaryActionSystemImage, let primaryAction {
                    Button(action: primaryAction) {
                        Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if !hints.isEmpty {
                HStack(spacing: 8) {
                    ForEach(hints) { hint in
                        Label {
                            Text(hint.title)
                        } icon: {
                            Text(hint.key)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(.background)
    }
}
