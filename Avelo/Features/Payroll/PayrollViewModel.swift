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
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
    }

    public func reload() {
        isLoading = true
        reloadTask?.cancel()
        let generation = UUID()
        reloadGeneration = generation
        error = nil
        let db = db
        let companyId = companyId
        let monthYear = monthYear
        reloadTask = Task.detached { [weak self] in
            do {
                let svc = PayrollService(db: db, companyId: companyId)
                let employees = try svc.listEmployees()
                let entries = try svc.listEntries(monthYear: monthYear)
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.employees = employees
                    self.entries = entries
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
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
