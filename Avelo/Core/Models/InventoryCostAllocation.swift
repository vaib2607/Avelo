import Foundation

/// Explicit audit link between one accounting cost line and one physical
/// inventory movement. Allocation policy and UI remain separate from this
/// persistence boundary.
public struct InventoryCostAllocation: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public let accountingId: LedgerLine.ID
    public let inventoryId: StockMovement.ID
    public let allocatedPaise: Int64
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                accountingId: LedgerLine.ID,
                inventoryId: StockMovement.ID,
                allocatedPaise: Int64,
                createdAt: Date = Date()) throws {
        guard allocatedPaise > 0 else {
            throw AppError.validation(.init(code: .internal, field: "allocatedPaise", message: "Inventory cost allocation must be greater than zero."))
        }
        self.id = id
        self.companyId = companyId
        self.accountingId = accountingId
        self.inventoryId = inventoryId
        self.allocatedPaise = allocatedPaise
        self.createdAt = createdAt
    }
}
