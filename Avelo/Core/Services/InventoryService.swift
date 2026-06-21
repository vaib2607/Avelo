import Foundation

public final class InventoryService: Sendable {

    public let db: SQLiteDatabase
    public let repository: InventoryRepository
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = InventoryRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public func listItems(includeArchived: Bool = false) throws -> [InventoryItem] {
        try ensureInventoryEnabled()
        return try repository.listItems(companyId: companyId, includeArchived: includeArchived)
    }

    public func listItems(includeArchived: Bool = false, limit: Int, offset: Int = 0) throws -> [InventoryItem] {
        try ensureInventoryEnabled()
        return try repository.listItems(companyId: companyId, includeArchived: includeArchived, limit: limit, offset: offset)
    }

    public func findItem(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try ensureInventoryEnabled()
        return try repository.findItem(id: id)
    }

    public func createItem(code: String,
                           name: String,
                           unit: String,
                           valuationMethod: ValuationMethod = .fifo) throws -> InventoryItem {
        try ensureInventoryEnabled()
        let item = InventoryItem(
            companyId: companyId,
            code: code,
            name: name,
            unit: unit,
            valuationMethod: valuationMethod
        )
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.insertItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemCreated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
        return item
    }

    public func updateItem(_ item: InventoryItem) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.updateItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemUpdated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.archiveItem(id)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemDisabled,
                entityType: "inventory_item",
                entityId: id.uuidString
            )
        }
    }

    public func recordMovement(itemId: InventoryItem.ID,
                               date: Date,
                               type: InventoryItem.MovementType,
                               quantity: Int64,
                               ratePaise: Int64,
                               voucherId: Voucher.ID? = nil,
                               notes: String? = nil) throws {
        try ensureInventoryEnabled()
        let totalValuePaise = quantity * ratePaise
        let movement = StockMovement(
            id: UUID(),
            companyId: companyId,
            itemId: itemId,
            date: date,
            movementType: type,
            quantity: quantity,
            unitCostPaise: ratePaise,
            totalValuePaise: totalValuePaise,
            voucherId: voucherId,
            reason: notes
        )
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            let onHand = try repo.runningBalance(itemId: itemId, asOf: date).onHandQty
            let validation = StockMovementValidator().validate(StockMovementValidator.Input(
                itemId: itemId,
                date: date,
                movementType: type,
                quantity: quantity,
                unitCostPaise: ratePaise,
                totalValuePaise: totalValuePaise,
                currentOnHandQty: onHand
            ))
            if case .invalid(let errs) = validation {
                throw AppError.validation(errs[0])
            }
            try repo.insertMovement(movement)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockMovementPosted,
                entityType: "stock_movement",
                entityId: movement.id.uuidString,
                snapshotAfter: movement
            )
        }
    }

    public func stockAsOf(itemId: InventoryItem.ID, date: Date) throws -> InventoryRepository.ItemBalance {
        try ensureInventoryEnabled()
        return try repository.runningBalance(itemId: itemId, asOf: date)
    }

    public func linkItemToAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.setItemAccount(itemId: itemId, accountId: accountId)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemUpdated,
                entityType: "inventory_item",
                entityId: itemId.uuidString
            )
        }
    }

    private func ensureInventoryEnabled() throws {
        guard let company = try CompanyRepository(db: db).findById(companyId) else {
            throw AppError.notFound("Company")
        }
        guard company.isInventoryEnabled else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
    }
}
