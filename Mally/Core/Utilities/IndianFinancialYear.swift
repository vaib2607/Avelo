import Foundation

public enum IndianFinancialYear {

    public static func fyLabel(for date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
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
}
