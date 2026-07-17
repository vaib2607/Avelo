import SwiftUI
import Observation

@MainActor
@Observable
public final class BankingViewModel {

    public var accounts: [Account] = []
    public var selectedAccountId: Account.ID?
    public var asOf: Date = Date()
    public var result: BankReconciliationService.ReconciliationResult?
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
            guard let company = try CompanyRepository(db: db).findById(companyId) else {
                throw AppError.notFound("Company")
            }
            let groups = try AccountGroupRepository(db: db).listForCompany(companyId)
            let policy = try AccountEligibilityPolicy.loading(db: db, companyId: companyId)
            accounts = try AccountService(db: db, companyId: companyId)
                .listActiveAccounts()
                .filter { policy.evaluate(account: $0, for: .bankReconciliation, company: company, groups: groups).isEligible }
            if selectedAccountId == nil { selectedAccountId = accounts.first?.id }
            reconcile()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func reconcile() {
        guard let aid = selectedAccountId else { return }
        do {
            result = try BankReconciliationService(db: db, companyId: companyId)
                .reconcile(accountId: aid, asOf: asOf)
        } catch {
            self.error = AppError.wrap(error)
        }
    }
}
