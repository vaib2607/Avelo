import SwiftUI

public enum AppColors {
    public static let sidebarBackground = Color(NSColor.windowBackgroundColor)
    public static let sidebarSelected = Color.accentColor.opacity(0.18)
    public static let contentBackground = Color(NSColor.textBackgroundColor)
    public static let divider = Color(NSColor.separatorColor)

    public static let success = Color(red: 0.13, green: 0.55, blue: 0.30)
    public static let info    = Color(red: 0.20, green: 0.45, blue: 0.78)
    public static let warning = Color(red: 0.86, green: 0.55, blue: 0.10)
    public static let error   = Color(red: 0.78, green: 0.20, blue: 0.20)

    public static let debitTint  = Color(red: 0.20, green: 0.45, blue: 0.78)
    public static let creditTint = Color(red: 0.78, green: 0.40, blue: 0.20)

    public static let moneyPositive = Color(red: 0.10, green: 0.45, blue: 0.20)
    public static let moneyNegative = Color(red: 0.75, green: 0.20, blue: 0.20)

    public static let statusActive   = Color(red: 0.13, green: 0.55, blue: 0.30)
    public static let statusInactive = Color(white: 0.55)
    public static let statusLocked   = Color(red: 0.78, green: 0.30, blue: 0.30)
}
