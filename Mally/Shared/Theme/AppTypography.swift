import SwiftUI

public enum AppTypography {
    public static let displayFont   = Font.system(size: 26, weight: .semibold, design: .default)
    public static let titleFont     = Font.system(size: 18, weight: .semibold, design: .default)
    public static let headingFont   = Font.system(size: 14, weight: .semibold, design: .default)
    public static let bodyFont      = Font.system(size: 13, weight: .regular,  design: .default)
    public static let smallFont     = Font.system(size: 11, weight: .regular,  design: .default)
    public static let captionFont   = Font.system(size: 10, weight: .regular,  design: .default)
    public static let buttonFont    = Font.system(size: 13, weight: .medium,   design: .default)
    public static let monoFont      = Font.system(size: 13, weight: .regular,  design: .monospaced)
    public static let monoDigitFont = Font.system(size: 13, weight: .regular,  design: .monospaced)
    public static let shortcutFont  = Font.system(size: 11, weight: .medium,   design: .monospaced)
}
