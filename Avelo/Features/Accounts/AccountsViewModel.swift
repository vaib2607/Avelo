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
    public var limit: Int = 200
    public var offset: Int = 0
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        isLoading = true
        reloadTask?.cancel()
        let generation = UUID()
        reloadGeneration = generation
        error = nil
        let db = db
        let companyId = companyId
        let limit = limit
        let offset = offset
        reloadTask = Task.detached { [weak self] in
            do {
                let svc = AccountService(db: db, companyId: companyId)
                let accounts = try svc.listAccounts(limit: limit, offset: offset)
                let groups = try svc.listGroups()
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.accounts = accounts
                    self.groups = groups
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
        Task.detached { [weak self] in
            do {
                try AccountService(db: db, companyId: companyId).disableAccount(id)
                await self?.reload()
            } catch {
                await MainActor.run { [weak self] in self?.error = AppError.wrap(error) }
            }
        }
    }
}
