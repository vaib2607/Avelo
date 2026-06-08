import SwiftUI

public struct EmptyStateView: View {
    public let title: String
    public let message: String
    public let systemImage: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(title: String,
                message: String,
                systemImage: String = "tray",
                actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: AppMetrics.spacingLarge) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: AppMetrics.spacing) {
                Text(title)
                    .font(AppTypography.titleFont)
                Text(message)
                    .font(AppTypography.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppMetrics.paddingLarge * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
