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
<<<<<<< HEAD
    public var pagination = PaginationState()
    public var isLoading: Bool = false
    public var error: AppError?

    public var limit: Int {
        get { pagination.limit }
        set { pagination.limit = max(1, newValue) }
    }

    public var offset: Int {
        get { pagination.offset }
        set { pagination.offset = max(0, newValue) }
    }

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()
=======
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
>>>>>>> origin/main

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        isLoading = true
<<<<<<< HEAD
        reloadTask?.cancel()
        let generation = UUID()
        reloadGeneration = generation
        error = nil
        let db = db
        let companyId = companyId
        let limit = limit
        let offset = offset
        let selectedGroupId = selectedGroupId
        let showDisabled = showDisabled
        let query = query
        reloadTask = Task.detached { [weak self] in
            do {
                let svc = AccountService(db: db, companyId: companyId)
                let filter = AccountRepository.Filter(
                    companyId: companyId,
                    groupId: selectedGroupId,
                    searchText: query,
                    includeInactive: showDisabled,
                    limit: limit,
                    offset: offset
                )
                let accounts = try svc.listAccounts(filter: filter)
                let totalCount = try svc.countAccounts(filter: filter)
                let groups = try svc.listGroups()
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.accounts = accounts
                    self.groups = groups
                    self.pagination.totalCount = totalCount
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
=======
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
>>>>>>> origin/main
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

    public var filtered: [Account] {
<<<<<<< HEAD
        accounts
    }

    public func reloadFirstPage() {
        pagination.reset()
        reload()
    }

    public func previousPage() {
        pagination.goPrevious()
        reload()
    }

    public func nextPage() {
        pagination.goNext()
        reload()
=======
        accounts.filter { acc in
            if !showDisabled && !acc.isActive { return false }
            if let gid = selectedGroupId, acc.groupId != gid { return false }
            if !query.isEmpty {
                return acc.name.localizedCaseInsensitiveContains(query)
                    || acc.code.localizedCaseInsensitiveContains(query)
            }
            return true
        }
>>>>>>> origin/main
    }

    public func disable(_ id: Account.ID) {
        let db = db
        let companyId = companyId
<<<<<<< HEAD
        Task.detached { [weak self] in
            do {
                try AccountService(db: db, companyId: companyId).disableAccount(id)
                await self?.reload()
            } catch {
                await MainActor.run { [weak self] in self?.error = AppError.wrap(error) }
=======
        Task.detached {
            do {
                try AccountService(db: db, companyId: companyId).disableAccount(id)
                await self.reload()
            } catch {
                await MainActor.run { self.error = AppError.wrap(error) }
>>>>>>> origin/main
            }
        }
    }
}
