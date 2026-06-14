import Foundation

public struct MasterDataRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func insert(_ c: CostCentre) throws {
        _ = c
        throw AppError.featureUnavailable("Cost centres are deferred outside the frozen schema.")
    }

    public func insert(_ c: CostCategory) throws {
        _ = c
        throw AppError.featureUnavailable("Cost categories are deferred outside the frozen schema.")
    }

    public func update(_ c: CostCentre) throws {
        _ = c
        throw AppError.featureUnavailable("Cost centres are deferred outside the frozen schema.")
    }

    public func update(_ c: CostCategory) throws {
        _ = c
        throw AppError.featureUnavailable("Cost categories are deferred outside the frozen schema.")
    }

    public func disableCostCentre(_ id: CostCentre.ID) throws {
        _ = id
        throw AppError.featureUnavailable("Cost centres are deferred outside the frozen schema.")
    }

    public func disableCostCategory(_ id: CostCategory.ID) throws {
        _ = id
        throw AppError.featureUnavailable("Cost categories are deferred outside the frozen schema.")
    }

    public func insert(_ b: Budget) throws {
        _ = b
        throw AppError.featureUnavailable("Budgets are deferred outside the frozen schema.")
    }

    public func listCostCentres(companyId: Company.ID) throws -> [CostCentre] {
        _ = companyId
        throw AppError.featureUnavailable("Cost centres are deferred outside the frozen schema.")
    }

    public func listCostCategories(companyId: Company.ID) throws -> [CostCategory] {
        _ = companyId
        throw AppError.featureUnavailable("Cost categories are deferred outside the frozen schema.")
    }
}
