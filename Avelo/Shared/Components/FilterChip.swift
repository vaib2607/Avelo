import SwiftUI

public struct FilterChip: View {
    public let label: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.smallFont)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : AppColors.divider, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
