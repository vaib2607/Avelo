import Foundation

public final class InventoryOrderService: Sendable {
    public struct DraftLine: Sendable {
        public let itemId: InventoryItem.ID
        public let quantity: Int64
        public let fulfilledQuantity: Int64
        public let unitRatePaise: Int64

        public init(itemId: InventoryItem.ID,
                    quantity: Int64,
                    fulfilledQuantity: Int64 = 0,
                    unitRatePaise: Int64 = 0) {
            self.itemId = itemId
            self.quantity = quantity
            self.fulfilledQuantity = fulfilledQuantity
            self.unitRatePaise = unitRatePaise
        }
    }

    public let db: SQLiteDatabase
    public let companyId: Company.ID
    private let repository: InventoryOrderRepository

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
        self.repository = InventoryOrderRepository(db: db)
    }

    public func createOrder(type: InventoryOrderType,
                            number: String,
                            partyAccountId: Account.ID,
                            orderDate: Date,
                            expectedDate: Date?,
                            lines: [DraftLine]) throws -> InventoryOrder {
        try ensureInventoryEnabled()
        guard !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation(ValidationError(code: .internal, field: "number", message: "Order number is required."))
        }
        guard !lines.isEmpty else {
            throw AppError.validation(ValidationError(code: .internal, field: "lines", message: "At least one order line is required."))
        }
        guard let party = try AccountRepository(db: db).findById(partyAccountId), party.companyId == companyId, party.isActive else {
            throw AppError.validation(ValidationError(code: .voucherAccountInactive, field: "partyAccountId", message: "Party account must belong to this company and be active."))
        }
        let inventory = InventoryRepository(db: db)
        let order = InventoryOrder(
            companyId: companyId,
            orderType: type,
            number: number,
            partyAccountId: partyAccountId,
            orderDate: orderDate,
            expectedDate: expectedDate
        )
        let orderLines = try lines.map { draft -> InventoryOrderLine in
            guard draft.quantity > 0 else {
                throw AppError.validation(ValidationError(code: .stockMovementQuantityZero, field: "quantity", message: "Order quantity must be greater than zero."))
            }
            guard draft.fulfilledQuantity >= 0, draft.fulfilledQuantity <= draft.quantity else {
                throw AppError.validation(ValidationError(code: .stockMovementCostMismatch, field: "fulfilledQuantity", message: "Fulfilled quantity must be within the ordered quantity."))
            }
            guard draft.unitRatePaise >= 0 else {
                throw AppError.validation(ValidationError(code: .stockMovementCostMismatch, field: "unitRatePaise", message: "Unit rate cannot be negative."))
            }
            guard let item = try inventory.findItemById(draft.itemId), item.companyId == companyId, item.isActive else {
                throw AppError.validation(ValidationError(code: .internal, field: "itemId", message: "Order item must belong to this company and be active."))
            }
            return InventoryOrderLine(
                companyId: companyId,
                orderId: order.id,
                itemId: draft.itemId,
                quantity: draft.quantity,
                fulfilledQuantity: draft.fulfilledQuantity,
                unitRatePaise: draft.unitRatePaise
            )
        }
        try repository.insertOrder(order, lines: orderLines)
        return order
    }

    public func pendingLines(type: InventoryOrderType? = nil) throws -> [PendingInventoryOrderLine] {
        try ensureInventoryEnabled()
        return try repository.pendingLines(companyId: companyId, orderType: type)
    }

    public func setReorderLevel(itemId: InventoryItem.ID,
                                minimumQuantity: Int64,
                                reorderQuantity: Int64) throws {
        try ensureInventoryEnabled()
        guard minimumQuantity >= 0, reorderQuantity >= 0 else {
            throw AppError.validation(ValidationError(code: .stockMovementCostMismatch, field: "quantity", message: "Reorder quantities cannot be negative."))
        }
        guard let item = try InventoryRepository(db: db).findItemById(itemId), item.companyId == companyId, item.isActive else {
            throw AppError.validation(ValidationError(code: .internal, field: "itemId", message: "Reorder item must belong to this company and be active."))
        }
        let level = InventoryReorderLevel(
            id: UUID(),
            companyId: companyId,
            itemId: itemId,
            minimumQuantity: minimumQuantity,
            reorderQuantity: reorderQuantity,
            createdAt: Date(),
            updatedAt: Date()
        )
        try repository.upsertReorderLevel(level)
    }

    public func reorderAlerts(asOfDate: Date) throws -> [ReorderAlert] {
        try repository.reorderAlerts(companyId: companyId, asOfDate: asOfDate)
    }

    private func ensureInventoryEnabled() throws {
        guard try CompanyRepository(db: db).findById(companyId)?.isInventoryEnabled == true else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
    }
}
