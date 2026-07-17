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
<<<<<<< HEAD
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()
=======
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
=======
>>>>>>> origin/main
        let db = db
        let companyId = companyId
        let query = query
        let entityTypeFilter = entityTypeFilter
        let fromDate = fromDate
        let toDate = toDate
<<<<<<< HEAD
        reloadTask = Task.detached { [weak self] in
=======
        Task.detached {
>>>>>>> origin/main
            do {
                let repo = AuditRepository(db: db)
                var f = AuditRepository.Filter(companyId: companyId, limit: 1000)
                f.searchText = query.isEmpty ? nil : query
                f.entityType = entityTypeFilter.isEmpty ? nil : entityTypeFilter
                f.fromDate = fromDate
                f.toDate = toDate
                let events = try repo.list(filter: f)
<<<<<<< HEAD
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
=======
                await MainActor.run {
>>>>>>> origin/main
                    self.events = events
                    self.isLoading = false
                }
            } catch {
<<<<<<< HEAD
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
=======
                await MainActor.run {
>>>>>>> origin/main
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

    public var entityTypes: [String] {
        Array(Set(events.map { $0.entityType })).sorted()
    }
}
