import Foundation

public enum PartyUsage: String, CaseIterable, Sendable, Codable, Identifiable {
    case customer
    case supplier
    case both

    public var id: String { rawValue }

    public var permitsCustomerUse: Bool { self == .customer || self == .both }
    public var permitsSupplierUse: Bool { self == .supplier || self == .both }
}

public struct PartyProfile: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Account.ID

    public let accountId: Account.ID
    public let companyId: Company.ID
    public var usage: PartyUsage
    public var creditLimitPaise: Int64?
    public var defaultCreditPeriodDays: Int?
    public var maintainBillwise: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public var id: ID { accountId }

    public init(accountId: Account.ID,
                companyId: Company.ID,
                usage: PartyUsage,
                creditLimitPaise: Int64? = nil,
                defaultCreditPeriodDays: Int? = nil,
                maintainBillwise: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.accountId = accountId
        self.companyId = companyId
        self.usage = usage
        self.creditLimitPaise = creditLimitPaise
        self.defaultCreditPeriodDays = defaultCreditPeriodDays
        self.maintainBillwise = maintainBillwise
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
