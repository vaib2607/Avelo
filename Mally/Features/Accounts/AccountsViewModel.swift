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
        defer { isLoading = false }
        do {
            let svc = AccountService(db: db, companyId: companyId)
            accounts = try svc.listAccounts()
            groups = try svc.listGroups()
        } catch {
            self.error = AppError.wrap(error)
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
        do {
            try AccountService(db: db, companyId: companyId).disableAccount(id)
            reload()
        } catch { self.error = AppError.wrap(error) }
    }
}
