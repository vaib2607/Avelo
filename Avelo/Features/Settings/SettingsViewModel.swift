import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
public final class SettingsViewModel {

    public var financialYears: [FinancialYear] = []
    public var company: Company?
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            company = try CompanyRepository(db: db).findById(companyId)
            financialYears = try FinancialYearService(db: db, companyId: companyId).list()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func setInventoryEnabled(_ enabled: Bool) {
        guard var company else { return }
        do {
            company.isInventoryEnabled = enabled
            if !enabled || !company.inventoryLinkMode.isAvailableForProduction {
                company.inventoryLinkMode = .manual
            }
            try CompanyRepository(db: db).update(company)
            reload()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func lock(_ id: FinancialYear.ID) {
        do { try FinancialYearService(db: db, companyId: companyId).lock(id); reload() }
        catch { self.error = AppError.wrap(error) }
    }

    public func unlock(_ id: FinancialYear.ID) {
        do { try FinancialYearService(db: db, companyId: companyId).unlock(id); reload() }
        catch { self.error = AppError.wrap(error) }
    }

    public func close(_ id: FinancialYear.ID) {
        do { try FinancialYearService(db: db, companyId: companyId).close(id); reload() }
        catch { self.error = AppError.wrap(error) }
    }
}
