import Foundation

public struct CostCentre: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public var code: String
    public var name: String
    public var isActive: Bool
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, code: String, name: String, isActive: Bool = true, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.code = code; self.name = name; self.isActive = isActive; self.createdAt = createdAt
    }
}

public struct CostCategory: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public var code: String
    public var name: String
    public var isActive: Bool
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, code: String, name: String, isActive: Bool = true, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.code = code; self.name = name; self.isActive = isActive; self.createdAt = createdAt
    }
}

public struct Budget: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public var financialYearId: FinancialYear.ID
    public var costCentreId: CostCentre.ID?
    public var code: String
    public var name: String
    public var plannedPaise: Int64
    public var actualPaise: Int64
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, financialYearId: FinancialYear.ID, costCentreId: CostCentre.ID? = nil, code: String, name: String, plannedPaise: Int64, actualPaise: Int64 = 0, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.financialYearId = financialYearId; self.costCentreId = costCentreId; self.code = code; self.name = name; self.plannedPaise = plannedPaise; self.actualPaise = actualPaise; self.createdAt = createdAt
    }
}
