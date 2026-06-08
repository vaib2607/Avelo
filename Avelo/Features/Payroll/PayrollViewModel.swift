import SwiftUI
import Observation

@MainActor
@Observable
public final class PayrollViewModel {

    public var employees: [PayrollEmployee] = []
    public var entries: [PayrollEntry] = []
    public var query: String = ""
    public var monthYear: Int = Calendar.current.component(.year, from: Date()) * 100 + Calendar.current.component(.month, from: Date())
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            let svc = PayrollService(db: db, companyId: companyId)
            employees = try svc.listEmployees()
            entries = try svc.listEntries(monthYear: monthYear)
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public var filtered: [PayrollEmployee] {
        guard !query.isEmpty else { return employees }
        return employees.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.employeeCode.localizedCaseInsensitiveContains(query)
        }
    }
}
