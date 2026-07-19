import Foundation

/// AVL-P1-036: describes how to shift a report's base date to compute its
/// comparative (second) column. Pure date arithmetic only — FY resolution
/// for the shifted date stays in `ReportsViewModel.financialYearID(containing:)`,
/// and this never touches which report values are correct, only which date
/// they're asked for.
public struct ComparativePeriod: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case priorYear
        case priorMonth
        case priorQuarter
        case custom(monthsBack: Int)
    }

    public let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public static let priorYear = ComparativePeriod(mode: .priorYear)
    public static let priorMonth = ComparativePeriod(mode: .priorMonth)
    public static let priorQuarter = ComparativePeriod(mode: .priorQuarter)

    /// `monthsBack` must be positive; non-positive values fall back to
    /// `.priorMonth` rather than shifting forward or not at all.
    public static func custom(monthsBack: Int) -> ComparativePeriod {
        ComparativePeriod(mode: monthsBack > 0 ? .custom(monthsBack: monthsBack) : .priorMonth)
    }

    /// Matches the exact `Calendar(identifier: .gregorian)` construction the
    /// hardcoded prior-year logic used, so the default mode reproduces
    /// today's behavior bit-for-bit.
    public func shift(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        switch mode {
        case .priorYear:
            return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        case .priorMonth:
            return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .priorQuarter:
            return calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .custom(let monthsBack):
            return calendar.date(byAdding: .month, value: -monthsBack, to: date) ?? date
        }
    }

    /// Comparative column header text — single source of truth, replacing
    /// every hardcoded "Prior Year (₹)" literal in the Reports views.
    public var columnLabel: String {
        switch mode {
        case .priorYear: return "Prior Year (₹)"
        case .priorMonth: return "Prior Month (₹)"
        case .priorQuarter: return "Prior Quarter (₹)"
        case .custom(let monthsBack): return "\(monthsBack)mo Prior (₹)"
        }
    }
}
