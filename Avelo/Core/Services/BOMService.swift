import Foundation

public final class BOMService: Sendable {
    public let db: SQLiteDatabase
    public let repository: BOMRepository
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = BOMRepository(db: db)
        self.companyId = companyId
    }

    public func saveBOM(assemblyItemId: InventoryItem.ID,
                        outputQuantity: Double,
                        components: [BOMComponent]) throws {
        let bom = BillOfMaterials(companyId: companyId,
                                  assemblyItemId: assemblyItemId,
                                  outputQuantity: outputQuantity)
        let normalized = components.enumerated().map { idx, c in
            BOMComponent(id: c.id,
                         companyId: companyId,
                         bomId: bom.id,
                         componentItemId: c.componentItemId,
                         quantity: c.quantity,
                         lineOrder: idx)
        }
        try db.write { tx in
            let repo = BOMRepository(db: tx)
            try repo.upsertBOM(bom)
            try repo.upsertComponents(normalized)
        }
    }

    public func loadBOM(for assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        try repository.loadBOM(companyId: companyId, assemblyItemId: assemblyItemId)
    }
}
