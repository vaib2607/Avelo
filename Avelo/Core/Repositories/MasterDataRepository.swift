import Foundation

public struct MasterDataRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func insert(_ c: CostCentre) throws {
        try db.execute("INSERT INTO avelo_cost_centres (id, company_id, code, name, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(c.id.uuidString), .text(c.companyId.uuidString), .text(c.code), .text(c.name), .bool(c.isActive), .timestamp(c.createdAt)])
    }
    public func insert(_ c: CostCategory) throws {
        try db.execute("INSERT INTO avelo_cost_categories (id, company_id, code, name, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(c.id.uuidString), .text(c.companyId.uuidString), .text(c.code), .text(c.name), .bool(c.isActive), .timestamp(c.createdAt)])
    }
    public func update(_ c: CostCentre) throws {
        try db.execute("UPDATE avelo_cost_centres SET code = ?, name = ?, is_active = ? WHERE id = ?",
                       [.text(c.code), .text(c.name), .bool(c.isActive), .text(c.id.uuidString)])
    }
    public func update(_ c: CostCategory) throws {
        try db.execute("UPDATE avelo_cost_categories SET code = ?, name = ?, is_active = ? WHERE id = ?",
                       [.text(c.code), .text(c.name), .bool(c.isActive), .text(c.id.uuidString)])
    }
    public func disableCostCentre(_ id: CostCentre.ID) throws {
        try db.execute("UPDATE avelo_cost_centres SET is_active = 0 WHERE id = ?", [.text(id.uuidString)])
    }
    public func disableCostCategory(_ id: CostCategory.ID) throws {
        try db.execute("UPDATE avelo_cost_categories SET is_active = 0 WHERE id = ?", [.text(id.uuidString)])
    }
    public func insert(_ b: Budget) throws {
        try db.execute("INSERT INTO avelo_budgets (id, company_id, financial_year_id, cost_centre_id, code, name, planned_paise, actual_paise, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                       [.text(b.id.uuidString), .text(b.companyId.uuidString), .text(b.financialYearId.uuidString), .optionalText(b.costCentreId?.uuidString), .text(b.code), .text(b.name), .integer(b.plannedPaise), .integer(b.actualPaise), .timestamp(b.createdAt)])
    }
    public func listCostCentres(companyId: Company.ID) throws -> [CostCentre] {
        try db.query("SELECT id, company_id, code, name, is_active, created_at FROM avelo_cost_centres WHERE company_id = ? ORDER BY code", bind: [.text(companyId.uuidString)]) {
            CostCentre(id: try UUIDParsing.required($0.text("id"), field: "avelo_cost_centres.id"), companyId: try UUIDParsing.required($0.text("company_id"), field: "avelo_cost_centres.company_id"), code: $0.text("code"), name: $0.text("name"), isActive: $0.bool("is_active"), createdAt: try $0.timestamp("created_at"))
        }
    }
    public func listCostCategories(companyId: Company.ID) throws -> [CostCategory] {
        try db.query("SELECT id, company_id, code, name, is_active, created_at FROM avelo_cost_categories WHERE company_id = ? ORDER BY code", bind: [.text(companyId.uuidString)]) {
            CostCategory(id: try UUIDParsing.required($0.text("id"), field: "avelo_cost_categories.id"), companyId: try UUIDParsing.required($0.text("company_id"), field: "avelo_cost_categories.company_id"), code: $0.text("code"), name: $0.text("name"), isActive: $0.bool("is_active"), createdAt: try $0.timestamp("created_at"))
        }
    }
}
