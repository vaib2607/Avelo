import Foundation

public enum DateFormatters {
    public static let isoDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public static let isoTimestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return df
    }()

    public static let displayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_IN")
        df.timeZone = TimeZone.current
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    public static let displayDateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_IN")
        df.timeZone = TimeZone.current
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df
    }()

    public static func isoDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    public static func isoTimestamp(_ date: Date) -> String {
        isoTimestampFormatter.string(from: date)
    }

    public static func parseDate(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return isoDateFormatter.date(from: s)
    }

    public static func parseTimestamp(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return isoTimestampFormatter.date(from: s)
    }

    public static func displayDate(_ date: Date) -> String {
        displayDateFormatter.string(from: date)
    }

    public static func displayDateTime(_ date: Date) -> String {
        displayDateTimeFormatter.string(from: date)
    }
}
