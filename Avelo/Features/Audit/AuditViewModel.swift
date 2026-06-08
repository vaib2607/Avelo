import SwiftUI
import Observation

@MainActor
@Observable
public final class AuditViewModel {

    public var events: [AuditEvent] = []
    public var query: String = ""
    public var entityTypeFilter: String = ""
    public var fromDate: Date?
    public var toDate: Date?
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
            let repo = AuditRepository(db: db)
            var f = AuditRepository.Filter(companyId: companyId, limit: 1000)
            f.searchText = query.isEmpty ? nil : query
            f.entityType = entityTypeFilter.isEmpty ? nil : entityTypeFilter
            f.fromDate = fromDate
            f.toDate = toDate
            events = try repo.list(filter: f)
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public var entityTypes: [String] {
        Array(Set(events.map { $0.entityType })).sorted()
    }
}
