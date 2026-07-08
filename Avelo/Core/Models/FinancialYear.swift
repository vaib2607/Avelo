import Foundation

public struct FinancialYear: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var label: String
    public var startDate: Date
    public var endDate: Date
    public var booksBeginDate: Date
    public var isLocked: Bool
    public var isClosed: Bool
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                label: String,
                startDate: Date,
                endDate: Date,
                booksBeginDate: Date,
                isLocked: Bool = false,
                isClosed: Bool = false,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
        self.booksBeginDate = booksBeginDate
        self.isLocked = isLocked
        self.isClosed = isClosed
        self.createdAt = createdAt
    }

    public func contains(date: Date) -> Bool {
        let cal = DateFormatters.utcCalendar
        let day = cal.startOfDay(for: date)
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        return day >= s && day <= e
    }
}
