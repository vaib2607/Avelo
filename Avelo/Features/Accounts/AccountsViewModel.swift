import SwiftUI
import Observation

@MainActor
@Observable
public final class AccountsViewModel {

    public var accounts: [Account] = []
    public var groups: [AccountGroup] = []
    public var query: String = ""
    public var selectedGroupId: AccountGroup.ID?
    public var showDisabled: Bool = false
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
        let db = db
        let companyId = companyId
        Task.detached {
            do {
                let svc = AccountService(db: db, companyId: companyId)
                let accounts = try svc.listAccounts()
                let groups = try svc.listGroups()
                await MainActor.run {
                    self.accounts = accounts
                    self.groups = groups
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

    public var filtered: [Account] {
        accounts.filter { acc in
            if !showDisabled && !acc.isActive { return false }
            if let gid = selectedGroupId, acc.groupId != gid { return false }
            if !query.isEmpty {
                return acc.name.localizedCaseInsensitiveContains(query)
                    || acc.code.localizedCaseInsensitiveContains(query)
            }
            return true
        }
    }

    public func disable(_ id: Account.ID) {
        let db = db
        let companyId = companyId
        Task.detached {
            do {
                try AccountService(db: db, companyId: companyId).disableAccount(id)
                await self.reload()
            } catch {
                await MainActor.run { self.error = AppError.wrap(error) }
            }
        }
    }
}
