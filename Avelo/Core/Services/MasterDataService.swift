import Foundation

public final class MasterDataService: Sendable {

    public let db: SQLiteDatabase
    public let repository: MasterDataRepository
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = MasterDataRepository(db: db)
        self.companyId = companyId
    }

    public func listCostCentres() throws -> [CostCentre] {
        try repository.listCostCentres(companyId: companyId)
    }

    public func listCostCategories() throws -> [CostCategory] {
        try repository.listCostCategories(companyId: companyId)
    }

    public func createCostCentre(code: String, name: String) throws -> CostCentre {
        let centre = CostCentre(companyId: companyId, code: code, name: name)
        try repository.insert(centre)
        return centre
    }

    public func createCostCategory(code: String, name: String) throws -> CostCategory {
        let category = CostCategory(companyId: companyId, code: code, name: name)
        try repository.insert(category)
        return category
    }

    public func updateCostCentre(_ centre: CostCentre) throws {
        try repository.update(centre)
    }

    public func updateCostCategory(_ category: CostCategory) throws {
        try repository.update(category)
    }

    public func disableCostCentre(_ id: CostCentre.ID) throws {
        try repository.disableCostCentre(id)
    }

    public func disableCostCategory(_ id: CostCategory.ID) throws {
        try repository.disableCostCategory(id)
    }
}
