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
            accounts = try AccountService(db: db, companyId: companyId)
                .listActiveAccounts()
                .filter { ($0.code.uppercased().contains("BANK")) || ($0.name.uppercased().contains("BANK")) }
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
