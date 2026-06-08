import SwiftUI

public struct ConfirmationDialog: View {
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let cancelTitle: String
    public let isDestructive: Bool
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(title: String,
                message: String,
                confirmTitle: String = "Confirm",
                cancelTitle: String = "Cancel",
                isDestructive: Bool = false,
                onConfirm: @escaping () -> Void,
                onCancel: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.spacingLarge) {
            VStack(alignment: .leading, spacing: AppMetrics.spacing) {
                Text(title)
                    .font(AppTypography.titleFont)
                Text(message)
                    .font(AppTypography.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .tint(isDestructive ? AppColors.error : .accentColor)
            }
        }
        .padding(AppMetrics.paddingLarge)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
    }
}
