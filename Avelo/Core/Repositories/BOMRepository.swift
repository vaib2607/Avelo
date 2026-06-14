import Foundation

public struct BOMRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) { self.db = db }

    public func upsertBOM(_ bom: BillOfMaterials) throws {
        _ = bom
        throw AppError.featureUnavailable("Bills of materials are deferred outside the frozen schema.")
    }

    public func upsertComponents(_ components: [BOMComponent]) throws {
        _ = components
        throw AppError.featureUnavailable("Bills of materials are deferred outside the frozen schema.")
    }

    public func loadBOM(companyId: Company.ID, assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        _ = (companyId, assemblyItemId)
        throw AppError.featureUnavailable("Bills of materials are deferred outside the frozen schema.")
    }
}
