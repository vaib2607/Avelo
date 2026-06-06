import SwiftUI

public enum StatusBadgeStyle {
    case active
    case inactive
    case locked
    case success
    case warning
    case error
    case info
    case neutral

    var fillColor: Color {
        switch self {
        case .active, .success: return AppColors.statusActive.opacity(0.18)
        case .inactive, .neutral: return Color.gray.opacity(0.18)
        case .locked, .error: return AppColors.statusLocked.opacity(0.18)
        case .warning: return AppColors.warning.opacity(0.18)
        case .info: return AppColors.info.opacity(0.18)
        }
    }

    var textColor: Color {
        switch self {
        case .active, .success: return AppColors.statusActive
        case .inactive, .neutral: return .secondary
        case .locked, .error: return AppColors.statusLocked
        case .warning: return AppColors.warning
        case .info: return AppColors.info
        }
    }
}

public struct StatusBadge: View {
    public let text: String
    public let style: StatusBadgeStyle

    public init(_ text: String, style: StatusBadgeStyle) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(AppTypography.smallFont)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(style.fillColor))
            .foregroundStyle(style.textColor)
    }
}
