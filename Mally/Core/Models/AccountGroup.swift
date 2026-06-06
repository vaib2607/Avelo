import Foundation

public enum AccountNature: String, CaseIterable, Sendable, Codable, Identifiable {
    case assets
    case liabilities
    case income
    case expense

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .assets:      return "Assets"
        case .liabilities: return "Liabilities"
        case .income:      return "Income"
        case .expense:     return "Expense"
        }
    }

    public var normalBalance: EntrySide {
        switch self {
        case .assets, .expense:     return .debit
        case .liabilities, .income: return .credit
        }
    }
}

public struct AccountGroup: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var parentGroupId: ID?
    public var code: String
    public var name: String
    public var nature: AccountNature
    public var isActive: Bool
    public var sortOrder: Int
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                parentGroupId: ID? = nil,
                code: String,
                name: String,
                nature: AccountNature,
                isActive: Bool = true,
                sortOrder: Int = 0,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.parentGroupId = parentGroupId
        self.code = code
        self.name = name
        self.nature = nature
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
