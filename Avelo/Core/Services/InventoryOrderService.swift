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
        guard let company = try CompanyRepository(db: db).findById(companyId),
              let party = try AccountRepository(db: db).findById(partyAccountId) else {
            throw AppError.validation(ValidationError(code: .voucherAccountInactive, field: "partyAccountId", message: "Party account is missing."))
        }
        let partyEligibility = try AccountEligibilityPolicy.loading(db: db, companyId: companyId).evaluate(
            account: party,
            for: .orderParty(type),
            company: company,
            groups: try AccountGroupRepository(db: db).listForCompany(companyId)
        )
        guard partyEligibility.isEligible else {
            throw AppError.validation(ValidationError(
                code: .voucherAccountInactive,
                field: "partyAccountId",
                message: partyEligibility.rejectionReason ?? "Party account is not eligible for this order."
            ))
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
        try db.write { tx in
            try InventoryOrderRepository(db: tx).insertOrder(order, lines: orderLines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .inventoryOrderCreated,
                entityType: "inventory_order",
                entityId: order.id.uuidString,
                snapshotAfter: order
            )
        }
        return order
    }

    public func pendingLines(type: InventoryOrderType? = nil) throws -> [PendingInventoryOrderLine] {
        try ensureInventoryEnabled()
        return try repository.pendingLines(companyId: companyId, orderType: type)
    }

    public func orders(type: InventoryOrderType? = nil, status: InventoryOrderStatus? = nil) throws -> [InventoryOrder] {
        try ensureInventoryEnabled()
        return try repository.listOrders(companyId: companyId, orderType: type, status: status)
    }

    public func linesForOrder(_ orderId: InventoryOrder.ID) throws -> [InventoryOrderLine] {
        try ensureInventoryEnabled()
        guard try repository.findOrder(id: orderId, companyId: companyId) != nil else {
            throw AppError.notFound("Order")
        }
        return try repository.linesForOrder(orderId, companyId: companyId)
    }

    /// Records fulfilment against one order line. Deliberately manual, not
    /// linked to voucher posting — matches the plan's scope of a standalone
    /// pending-fulfilment workspace, not full order-to-invoice conversion.
    public func recordFulfillment(orderLineId: InventoryOrderLine.ID, fulfilledQuantity: Int64) throws {
        try ensureInventoryEnabled()
        guard let line = try repository.findOrderLine(id: orderLineId, companyId: companyId) else {
            throw AppError.notFound("Order line")
        }
        guard let order = try repository.findOrder(id: line.orderId, companyId: companyId) else {
            throw AppError.notFound("Order")
        }
        guard order.status == .open else {
            throw AppError.businessRule("Only open orders accept fulfilment updates.")
        }
        guard fulfilledQuantity >= 0, fulfilledQuantity <= line.quantity else {
            throw AppError.validation(ValidationError(code: .stockMovementCostMismatch, field: "fulfilledQuantity", message: "Fulfilled quantity must be within the ordered quantity."))
        }
        try db.write { tx in
            let repository = InventoryOrderRepository(db: tx)
            try repository.updateLineFulfillment(orderLineId, companyId: companyId, fulfilledQuantity: fulfilledQuantity)
            guard let updatedLine = try repository.findOrderLine(id: orderLineId, companyId: companyId) else {
                throw AppError.notFound("Order line")
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .inventoryOrderFulfilled,
                entityType: "inventory_order_line",
                entityId: orderLineId.uuidString,
                snapshotBefore: line,
                snapshotAfter: updatedLine,
                reason: "Fulfilled quantity set to \(fulfilledQuantity)"
            )
        }
    }

    public func closeOrder(_ orderId: InventoryOrder.ID) throws {
        try setOrderStatus(orderId, to: .closed)
    }

    public func cancelOrder(_ orderId: InventoryOrder.ID) throws {
        try setOrderStatus(orderId, to: .cancelled)
    }

    private func setOrderStatus(_ orderId: InventoryOrder.ID, to status: InventoryOrderStatus) throws {
        try ensureInventoryEnabled()
        guard let order = try repository.findOrder(id: orderId, companyId: companyId) else {
            throw AppError.notFound("Order")
        }
        guard order.status == .open else {
            throw AppError.businessRule("Only open orders can change status.")
        }
        try db.write { tx in
            let repository = InventoryOrderRepository(db: tx)
            try repository.updateOrderStatus(orderId, companyId: companyId, status: status)
            guard let updatedOrder = try repository.findOrder(id: orderId, companyId: companyId) else {
                throw AppError.notFound("Order")
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .inventoryOrderStatusChanged,
                entityType: "inventory_order",
                entityId: orderId.uuidString,
                snapshotBefore: order,
                snapshotAfter: updatedOrder,
                reason: "Status set to \(status)"
            )
        }
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
        try db.write { tx in
            try InventoryOrderRepository(db: tx).upsertReorderLevel(level)
            try AuditService(db: tx, companyId: companyId).record(
                action: .inventoryReorderLevelSet,
                entityType: "inventory_reorder_level",
                entityId: itemId.uuidString,
                snapshotAfter: level
            )
        }
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
