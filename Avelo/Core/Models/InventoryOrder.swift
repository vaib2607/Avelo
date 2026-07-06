import Foundation

public enum InventoryOrderType: String, CaseIterable, Sendable, Codable, Identifiable {
    case purchaseOrder
    case salesOrder

    public var id: String { rawValue }
}

public enum InventoryOrderStatus: String, CaseIterable, Sendable, Codable, Identifiable {
    case open
    case closed
    case cancelled

    public var id: String { rawValue }
}

public struct InventoryOrder: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var orderType: InventoryOrderType
    public var number: String
    public var partyAccountId: Account.ID
    public var orderDate: Date
    public var expectedDate: Date?
    public var status: InventoryOrderStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                orderType: InventoryOrderType,
                number: String,
                partyAccountId: Account.ID,
                orderDate: Date,
                expectedDate: Date? = nil,
                status: InventoryOrderStatus = .open,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.orderType = orderType
        self.number = number
        self.partyAccountId = partyAccountId
        self.orderDate = orderDate
        self.expectedDate = expectedDate
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct InventoryOrderLine: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public let orderId: InventoryOrder.ID
    public let itemId: InventoryItem.ID
    public var quantity: Int64
    public var fulfilledQuantity: Int64
    public var unitRatePaise: Int64
    public let createdAt: Date

    public var pendingQuantity: Int64 {
        guard fulfilledQuantity < quantity else { return 0 }
        return (try? CheckedMath.subtract(
            quantity,
            fulfilledQuantity,
            context: "calculating pending inventory order quantity"
        )) ?? 0
    }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                orderId: InventoryOrder.ID,
                itemId: InventoryItem.ID,
                quantity: Int64,
                fulfilledQuantity: Int64 = 0,
                unitRatePaise: Int64 = 0,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.orderId = orderId
        self.itemId = itemId
        self.quantity = quantity
        self.fulfilledQuantity = fulfilledQuantity
        self.unitRatePaise = unitRatePaise
        self.createdAt = createdAt
    }
}

public struct InventoryReorderLevel: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public let itemId: InventoryItem.ID
    public var minimumQuantity: Int64
    public var reorderQuantity: Int64
    public let createdAt: Date
    public var updatedAt: Date
}

public struct PendingInventoryOrderLine: Identifiable, Hashable, Sendable {
    public let id: InventoryOrderLine.ID
    public let orderId: InventoryOrder.ID
    public let orderType: InventoryOrderType
    public let orderNumber: String
    public let partyAccountName: String
    public let itemId: InventoryItem.ID
    public let itemName: String
    public let quantity: Int64
    public let fulfilledQuantity: Int64
    public let pendingQuantity: Int64
    public let expectedDate: Date?
}

public struct ReorderAlert: Identifiable, Hashable, Sendable {
    public let id: InventoryItem.ID
    public let itemName: String
    public let onHandQuantity: Int64
    public let minimumQuantity: Int64
    public let reorderQuantity: Int64
}
