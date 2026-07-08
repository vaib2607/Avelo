import Foundation

public enum IndianFinancialYear {

    /// Avelo persists all date-only values through a UTC-anchored ISO
    /// formatter (`DateFormatters.isoDateFormatter`), so that is the fixed
    /// reference frame for "which calendar day" a `Date` represents
    /// throughout the app. Extracting components with the device's ambient
    /// timezone instead (the previous behavior of this type) let the FY a
    /// date resolves to drift with the Mac's system timezone setting near a
    /// month boundary. Anchoring here to the same fixed UTC frame as
    /// `startDate`/`endDate` makes FY detection independent of device
    /// timezone (AVL-P0-023) without shifting the persisted calendar day.
    private static var referenceCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    public static func fyLabel(for date: Date) -> String {
        let cal = referenceCalendar
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let startYear: Int
        if month >= 4 {
            startYear = year
        } else {
            startYear = year - 1
        }
        let endYearShort = (startYear + 1) % 100
        return String(format: "%04d-%02d", startYear, endYearShort)
    }

    public static func startDate(ofFYStartingYear year: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = 4
        c.day = 1
        c.hour = 0; c.minute = 0; c.second = 0
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")
        return c.date ?? Date()
    }

    public static func endDate(ofFYStartingYear year: Int) -> Date {
        var c = DateComponents()
        c.year = year + 1
        c.month = 3
        c.day = 31
        c.hour = 23; c.minute = 59; c.second = 59
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")
        return c.date ?? Date()
    }

    public static func startYear(fromLabel label: String) -> Int? {
        let parts = label.split(separator: "-")
        guard let first = parts.first, let y = Int(first) else { return nil }
        return y
    }

    public static func start(for date: Date) -> Date {
        let cal = referenceCalendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let startYear = m >= 4 ? y : (y - 1)
        return startDate(ofFYStartingYear: startYear)
    }

    public static func end(for date: Date) -> Date {
        let cal = referenceCalendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let startYear = m >= 4 ? y : (y - 1)
        return endDate(ofFYStartingYear: startYear)
    }

    public struct DetectedFY: Sendable {
        public let label: String
        public let start: Date
        public let end: Date
    }

    public static func detect(now: Date = Date()) -> DetectedFY {
        DetectedFY(label: fyLabel(for: now), start: start(for: now), end: end(for: now))
    }
}
