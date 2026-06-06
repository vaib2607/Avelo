import Foundation

public final class CompanyService: Sendable {

    public let db: SQLiteDatabase
    public let repository: CompanyRepository
    public let audit: AuditService
    public let manager: DatabaseManager

    public init(db: SQLiteDatabase, companyId: Company.ID, manager: DatabaseManager) {
        self.db = db
        self.repository = CompanyRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.manager = manager
    }

    public func current() throws -> Company? {
        try repository.findById(audit.companyId)
    }

    public func update(_ company: Company) throws {
        var c = company
        c.updatedAt = Date()
        try repository.update(c)
        try audit.record(
            action: .companyUpdated,
            entityType: "company",
            entityId: c.id.uuidString,
            snapshotBefore: company,
            snapshotAfter: c
        )
    }

    public func setInventoryMode(enabled: Bool, linkMode: InventoryLinkMode) throws {
        guard var company = try current() else {
            throw AppError.notFound("Company")
        }
        let before = company
        company.isInventoryEnabled = enabled
        company.inventoryLinkMode = linkMode
        company.updatedAt = Date()
        try repository.update(company)
        try audit.record(
            action: .inventoryModeChanged,
            entityType: "company",
            entityId: company.id.uuidString,
            snapshotBefore: before,
            snapshotAfter: company
        )
    }

    public static func create(companyInput: CompanyInputValidator.Input,
                              fyInput: FinancialYearInputValidator.Input,
                              seedDefaults: Bool,
                              manager: DatabaseManager) async throws -> Company {
        let v1 = CompanyInputValidator().validate(companyInput)
        if case .invalid(let errs) = v1 {
            throw AppError.validation(errs[0])
        }
        let v2 = FinancialYearInputValidator().validate(fyInput)
        if case .invalid(let errs) = v2 {
            throw AppError.validation(errs[0])
        }

        let company = Company(
            name: companyInput.name.trimmingCharacters(in: .whitespacesAndNewlines),
            gstin: companyInput.gstin?.isEmpty == true ? nil : companyInput.gstin,
            pan:   companyInput.pan?.isEmpty   == true ? nil : companyInput.pan
        )
        let fy = FinancialYear(
            companyId: company.id,
            label: fyInput.label,
            startDate: fyInput.startDate,
            endDate: fyInput.endDate,
            booksBeginDate: fyInput.booksBeginDate
        )
        _ = try await manager.createCompanyFile(companyId: company.id)

        let db = try SQLiteDatabase(path: manager.companiesDirectory
                                            .appendingPathComponent("\(company.id.uuidString).sqlite")
                                            .path)
        defer { db.close() }

        let companyRepo = CompanyRepository(db: db)
        let fyRepo = FinancialYearRepository(db: db)
        _ = try companyRepo.insert(company)
        try fyRepo.insert(fy)
        try SeedLoader().loadDefaults(into: db,
                                       companyId: company.id,
                                       financialYearId: fy.id)

        let audit = AuditService(db: db, companyId: company.id)
        try audit.record(
            action: .companyCreated,
            entityType: "company",
            entityId: company.id.uuidString,
            snapshotAfter: company
        )
        try audit.record(
            action: .financialYearCreated,
            entityType: "financial_year",
            entityId: fy.id.uuidString,
            snapshotAfter: fy
        )

        let registry = RegistryRepository(db: try registryDb(manager: manager))
        try registry.register(CompanyRegistryEntry(
            id: company.id,
            name: company.name,
            sqliteFileName: "\(company.id.uuidString).sqlite"
        ))
        return company
    }

    static func registryDb(manager: DatabaseManager) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: manager.registryPath)
    }
}
