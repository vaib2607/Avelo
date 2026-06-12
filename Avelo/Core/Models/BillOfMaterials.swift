import Foundation

public struct BillOfMaterials: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var assemblyItemId: InventoryItem.ID
    public var outputQuantity: Double
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                assemblyItemId: InventoryItem.ID,
                outputQuantity: Double = 1,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.assemblyItemId = assemblyItemId
        self.outputQuantity = outputQuantity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BOMComponent: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var bomId: BillOfMaterials.ID
    public var componentItemId: InventoryItem.ID
    public var quantity: Double
    public var lineOrder: Int

    public init(id: ID = UUID(),
                companyId: Company.ID,
                bomId: BillOfMaterials.ID,
                componentItemId: InventoryItem.ID,
                quantity: Double,
                lineOrder: Int = 0) {
        self.id = id
        self.companyId = companyId
        self.bomId = bomId
        self.componentItemId = componentItemId
        self.quantity = quantity
        self.lineOrder = lineOrder
    }
}
