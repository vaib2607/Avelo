import Foundation

public enum DateFormatters {
<<<<<<< HEAD
    /// Fixed reference calendar for accounting-day comparisons (financial-year
    /// containment, employment windows, bank-reconciliation date tolerance,
    /// ageing buckets). All date-only values are persisted through the
    /// UTC-anchored `isoDateFormatter`, so day-boundary arithmetic must use
    /// this same fixed UTC frame rather than `Calendar(identifier: .gregorian)`'s
    /// ambient device timezone -- otherwise which accounting day a date falls
    /// on could shift with the Mac's system timezone setting (AVL-P0-023).
    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

=======
>>>>>>> origin/main
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

    public static let gstReturnFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_IN")
        df.timeZone = TimeZone.current
        df.dateFormat = "MMM yyyy"
        return df
    }()

<<<<<<< HEAD
=======
    public static let gstPeriodFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_IN")
        df.timeZone = TimeZone.current
        df.dateFormat = "MM/yyyy"
        return df
    }()

>>>>>>> origin/main
    public static let userDate: DateFormatter = displayDateFormatter
    public static let isoTimestamp: DateFormatter = isoTimestampFormatter
    public static let isoDate: DateFormatter = isoDateFormatter
    public static let gstReturn: DateFormatter = gstReturnFormatter
<<<<<<< HEAD

=======
    public static let gstPeriod: DateFormatter = gstPeriodFormatter

    public static func stringFromIsoDate(_ s: String) -> String { s }
>>>>>>> origin/main
    public static func parseTimestamp(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return isoTimestampFormatter.date(from: s)
    }

    public static func parseDate(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let d = isoDateFormatter.date(from: s) { return d }
        return displayDateFormatter.date(from: s)
    }

    public static func formatIsoDate(_ date: Date) -> String { isoDateFormatter.string(from: date) }
    public static func formatDisplayDate(_ date: Date) -> String { displayDateFormatter.string(from: date) }
    public static func formatDisplayDateTime(_ date: Date) -> String { displayDateTimeFormatter.string(from: date) }
    public static func formatIsoTimestamp(_ date: Date) -> String { isoTimestampFormatter.string(from: date) }
    public static func formatGstReturn(_ date: Date) -> String { gstReturnFormatter.string(from: date) }
<<<<<<< HEAD

    public static func displayDate(_ date: Date) -> String { formatDisplayDate(date) }
=======
    public static func formatGstPeriod(_ date: Date) -> String { gstPeriodFormatter.string(from: date) }

    public static func displayDate(_ date: Date) -> String { displayDateFormatter.string(from: date) }
>>>>>>> origin/main
}
