import SwiftUI
import Observation

@MainActor
@Observable
public final class InventoryOrdersViewModel {

    public var orders: [InventoryOrder] = []
    public var typeFilter: InventoryOrderType?
    public var statusFilter: InventoryOrderStatus? = .open
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    private var reloadGeneration: UUID = UUID()

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        isLoading = true
        error = nil
        let generation = UUID()
        reloadGeneration = generation
        let db = db
        let companyId = companyId
        let typeFilter = typeFilter
        let statusFilter = statusFilter
        Task.detached { [weak self] in
            do {
                let orders = try InventoryOrderService(db: db, companyId: companyId).orders(type: typeFilter, status: statusFilter)
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation else { return }
                    self.orders = orders
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation else { return }
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

    public func closeOrder(_ id: InventoryOrder.ID) {
        do {
            try InventoryOrderService(db: db, companyId: companyId).closeOrder(id)
            reload()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func cancelOrder(_ id: InventoryOrder.ID) {
        do {
            try InventoryOrderService(db: db, companyId: companyId).cancelOrder(id)
            reload()
        } catch {
            self.error = AppError.wrap(error)
        }
    }
}
