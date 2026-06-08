import SwiftUI

public enum BannerKind: Sendable, Equatable {
    case success(String)
    case info(String)
    case warning(String)
    case error(String)
}

public struct ErrorBanner: View {
    public let kind: BannerKind
    public let onDismiss: () -> Void

    public init(kind: BannerKind, onDismiss: @escaping () -> Void) {
        self.kind = kind
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AppMetrics.spacing) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(AppTypography.bodyFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, AppMetrics.padding)
        .padding(.vertical, AppMetrics.spacing)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var message: String {
        switch kind {
        case .success(let m), .info(let m), .warning(let m), .error(let m):
            return m
        }
    }

    private var tint: Color {
        switch kind {
        case .success: return AppColors.success
        case .info:    return AppColors.info
        case .warning: return AppColors.warning
        case .error:   return AppColors.error
        }
    }

    private var background: Color {
        tint.opacity(0.10)
    }

    private var iconName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
}
