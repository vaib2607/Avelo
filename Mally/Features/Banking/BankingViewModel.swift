import SwiftUI

@MainActor
public final class BankingViewModel: ObservableObject {

    @Published public var accounts: [Account] = []
    @Published public var selectedAccountId: Account.ID?
    @Published public var asOf: Date = Date()
    @Published public var result: BankReconciliationService.ReconciliationResult?
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
