import SwiftUI
import Observation

@MainActor
@Observable
public final class InventoryViewModel {

    public var items: [InventoryItem] = []
    public var query: String = ""
    public var includeArchived: Bool = false
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
        let includeArchived = includeArchived
        let limit = limit
        let offset = offset
        let query = query
        reloadTask = Task.detached { [weak self] in
            do {
                let filter = InventoryRepository.ItemFilter(
                    companyId: companyId,
                    includeArchived: includeArchived,
                    searchText: query,
                    limit: limit,
                    offset: offset
                )
                let service = InventoryService(db: db, companyId: companyId)
                let items = try service.listItems(filter: filter)
                let totalCount = try service.countItems(filter: filter)
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.items = items
                    self.pagination.totalCount = totalCount
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

    public var filtered: [InventoryItem] {
        items
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
    }

    public func archive(_ id: InventoryItem.ID) {
        let db = db
        let companyId = companyId
        Task.detached { [weak self] in
            do {
                try InventoryService(db: db, companyId: companyId).archiveItem(id)
                await self?.reload()
            } catch {
                await MainActor.run { [weak self] in self?.error = AppError.wrap(error) }
            }
        }
    }
}
