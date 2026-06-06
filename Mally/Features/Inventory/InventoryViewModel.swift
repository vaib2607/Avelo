import SwiftUI

@MainActor
public final class InventoryViewModel: ObservableObject {

    @Published public var items: [InventoryItem] = []
    @Published public var query: String = ""
    @Published public var includeArchived: Bool = false
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
            items = try InventoryService(db: db, companyId: companyId)
                .listItems(includeArchived: includeArchived)
        } catch {
            self.error = AppError.wrap(error)
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
        do {
            try InventoryService(db: db, companyId: companyId).archiveItem(id)
            reload()
        } catch { self.error = AppError.wrap(error) }
    }
}
