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
        try repository.listItems(companyId: companyId, includeArchived: includeArchived)
    }

    public func findItem(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try repository.findItem(id: id)
    }

    public func createItem(code: String,
                           name: String,
                           unit: String,
                           openingQuantity: Double,
                           openingRatePaise: Int64,
                           gstRate: Double = 0,
                           stockGroup: String? = nil,
                           stockCategory: String? = nil,
                           godown: String? = nil,
                           barcode: String? = nil,
                           hsnSac: String? = nil) throws -> InventoryItem {
        let item = InventoryItem(
            companyId: companyId,
            code: code,
            name: name,
            unit: unit,
            openingQuantity: openingQuantity,
            openingRatePaise: openingRatePaise,
            gstRate: gstRate,
            stockGroup: stockGroup,
            stockCategory: stockCategory,
            godown: godown,
            barcode: barcode,
            hsnSac: hsnSac,
            isArchived: false,
            linkedAccountId: nil
        )
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.insertItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .itemCreated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
        return item
    }

    public func updateItem(_ item: InventoryItem) throws {
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.updateItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .itemUpdated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.archiveItem(id)
            try AuditService(db: tx, companyId: companyId).record(
                action: .itemArchived,
                entityType: "inventory_item",
                entityId: id.uuidString
            )
        }
    }

    public func recordMovement(itemId: InventoryItem.ID,
                               date: Date,
                               type: InventoryItem.MovementType,
                               quantity: Double,
                               ratePaise: Int64,
                               voucherId: Voucher.ID? = nil,
                               batchNumber: String? = nil,
                               manufactureDate: Date? = nil,
                               expiryDate: Date? = nil,
                               notes: String? = nil) throws {
        let totalValuePaise = Int64((quantity * Double(ratePaise)).rounded())
        let onHand: Double
        do {
            onHand = try repository.runningBalance(itemId: itemId, asOf: date).onHandQty
        } catch {
            throw AppError.wrap(error)
        }
        let v = StockMovementValidator().validate(StockMovementValidator.Input(
            itemId: itemId,
            date: date,
            movementType: type,
            quantity: quantity,
            unitCostPaise: ratePaise,
            totalValuePaise: totalValuePaise,
            currentOnHandQty: onHand
        ))
        if case .invalid(let errs) = v {
            if errs.contains(where: { $0.code == .quantityExceedsStock }) {
                throw AppError.negativeStock(errs.first?.message ?? "Out quantity exceeds current stock.")
            }
            throw AppError.validation(errs[0])
        }
        let outTypes: Set<InventoryItem.MovementType> = [.stockOut, .sale, .purchaseReturn, .adjustmentOut]
        if outTypes.contains(type) && quantity > onHand {
            throw AppError.negativeStock("Out quantity exceeds current stock.")
        }
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
            batchNumber: batchNumber,
            manufactureDate: manufactureDate,
            expiryDate: expiryDate,
            reason: notes
        )
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.insertMovement(movement)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockMoved,
                entityType: "stock_movement",
                entityId: movement.id.uuidString,
                snapshotAfter: movement
            )
        }
    }

    public func stockAsOf(itemId: InventoryItem.ID, date: Date) throws -> InventoryRepository.ItemBalance {
        try repository.runningBalance(itemId: itemId, asOf: date)
    }

    public func linkItemToAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.setItemAccount(itemId: itemId, accountId: accountId)
            try AuditService(db: tx, companyId: companyId).record(
                action: .itemAccountLinked,
                entityType: "inventory_item",
                entityId: itemId.uuidString
            )
        }
    }
}
