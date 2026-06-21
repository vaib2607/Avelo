import SwiftUI
import Observation

@MainActor
@Observable
public final class InventoryViewModel {

    public var items: [InventoryItem] = []
    public var query: String = ""
    public var includeArchived: Bool = false
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
        let includeArchived = includeArchived
        let limit = limit
        let offset = offset
        reloadTask = Task.detached { [weak self] in
            do {
                let items = try InventoryService(db: db, companyId: companyId)
                    .listItems(includeArchived: includeArchived, limit: limit, offset: offset)
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.items = items
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
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
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
