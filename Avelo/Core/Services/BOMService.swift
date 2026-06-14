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
        _ = (assemblyItemId, outputQuantity, components)
        throw AppError.featureUnavailable("Bills of materials are deferred outside the frozen schema.")
    }

    public func loadBOM(for assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        _ = assemblyItemId
        throw AppError.featureUnavailable("Bills of materials are deferred outside the frozen schema.")
    }
}
