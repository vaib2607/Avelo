import SwiftUI

@MainActor
public final class AccountsViewModel: ObservableObject {

    @Published public var accounts: [Account] = []
    @Published public var groups: [AccountGroup] = []
    @Published public var query: String = ""
    @Published public var selectedGroupId: AccountGroup.ID?
    @Published public var showDisabled: Bool = false
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
