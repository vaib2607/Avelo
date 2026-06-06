import Foundation

public enum OpeningBalanceSide: String, CaseIterable, Sendable, Codable, Identifiable {
    case debit
    case credit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .debit:  return "Dr"
        case .credit: return "Cr"
        }
    }
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var groupId: AccountGroup.ID
    public var code: String
    public var name: String
    public var openingBalancePaise: Int64
    public var openingBalanceSide: OpeningBalanceSide
    public var isActive: Bool
    public var isBankAccount: Bool
    public var gstin: String?
    public var lastUsedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                groupId: AccountGroup.ID,
                code: String,
                name: String,
                openingBalancePaise: Int64 = 0,
                openingBalanceSide: OpeningBalanceSide = .debit,
                isActive: Bool = true,
                isBankAccount: Bool = false,
                gstin: String? = nil,
                lastUsedAt: Date? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.groupId = groupId
        self.code = code
        self.name = name
        self.openingBalancePaise = openingBalancePaise
        self.openingBalanceSide = openingBalanceSide
        self.isActive = isActive
        self.isBankAccount = isBankAccount
        self.gstin = gstin
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func signedOpeningBalancePaise() -> Int64 {
        switch openingBalanceSide {
        case .debit:  return openingBalancePaise
        case .credit: return -openingBalancePaise
        }
    }
}
