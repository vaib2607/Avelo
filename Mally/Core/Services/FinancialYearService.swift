import Foundation

public final class FinancialYearService: Sendable {

    public let db: SQLiteDatabase
    public let repository: FinancialYearRepository
    public let audit: AuditService

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = FinancialYearRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
    }

    public func list() throws -> [FinancialYear] {
        try repository.listForCompany(audit.companyId)
    }

    public func openYears() throws -> [FinancialYear] {
        try repository.findOpenForCompany(audit.companyId)
    }

    public func mostRecent() throws -> FinancialYear? {
        try repository.findMostRecent(audit.companyId)
    }

    public func create(label: String,
                       startDate: Date,
                       endDate: Date,
                       booksBeginDate: Date) throws -> FinancialYear {
        let input = FinancialYearInputValidator.Input(
            label: label, startDate: startDate, endDate: endDate,
            booksBeginDate: booksBeginDate
        )
        let result = FinancialYearInputValidator().validate(input)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        let fy = FinancialYear(
            companyId: audit.companyId,
            label: label,
            startDate: startDate,
            endDate: endDate,
            booksBeginDate: booksBeginDate
        )
        try db.write { tx in
            let repo = FinancialYearRepository(db: tx)
            try repo.insert(fy)
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .financialYearCreated,
                entityType: "financial_year",
                entityId: fy.id.uuidString,
                snapshotAfter: fy
            )
        }
        return fy
    }

    public func lock(_ id: FinancialYear.ID, reason: String? = nil) throws {
        try repository.lock(id)
        try audit.record(
            action: .financialYearLocked,
            entityType: "financial_year",
            entityId: id.uuidString,
            reason: reason
        )
    }

    public func unlock(_ id: FinancialYear.ID, reason: String? = nil) throws {
        try repository.unlock(id)
        try audit.record(
            action: .fyUnlocked,
            entityType: "financial_year",
            entityId: id.uuidString,
            reason: reason
        )
    }

    public func close(_ id: FinancialYear.ID) throws {
        try repository.markClosed(id)
        try audit.record(
            action: .financialYearClosed,
            entityType: "financial_year",
            entityId: id.uuidString
        )
    }
}
