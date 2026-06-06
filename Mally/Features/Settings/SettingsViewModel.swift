import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {

    @Published public var financialYears: [FinancialYear] = []
    @Published public var isLoading: Bool = false
    @Published public var error: AppError?

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
            financialYears = try FinancialYearService(db: db, companyId: companyId).list()
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
