import SwiftUI
import Observation

@MainActor
@Observable
public final class InventoryViewModel {

    public var items: [InventoryItem] = []
    public var query: String = ""
    public var includeArchived: Bool = false
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
        let includeArchived = includeArchived
        Task.detached {
            do {
                let items = try InventoryService(db: db, companyId: companyId)
                    .listItems(includeArchived: includeArchived)
                await MainActor.run {
                    self.items = items
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
        Task.detached {
            do {
                try InventoryService(db: db, companyId: companyId).archiveItem(id)
                await self.reload()
            } catch {
                await MainActor.run { self.error = AppError.wrap(error) }
            }
        }
    }
}
