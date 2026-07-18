import Foundation

/// Canonical persistence boundary for explicitly supplied landed-cost links.
/// It is intentionally policy-free: callers determine allocation basis and
/// residual-paise handling before entering the transaction.
public struct InventoryCostAllocationRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func insert(_ allocation: InventoryCostAllocation) throws {
        try db.execute(
            """
            INSERT INTO trn_inventory_cost_allocations
            (id, company_id, accounting_id, inventory_id, allocated_paise, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(allocation.id.uuidString),
                .text(allocation.companyId.uuidString),
                .text(allocation.accountingId.uuidString),
                .text(allocation.inventoryId.uuidString),
                .integer(allocation.allocatedPaise),
                .timestamp(allocation.createdAt)
            ]
        )
    }

    public func hasAllocation(accountingId: LedgerLine.ID, inventoryId: StockMovement.ID) throws -> Bool {
        (try db.queryOne(
            "SELECT 1 FROM trn_inventory_cost_allocations WHERE accounting_id = ? AND inventory_id = ?",
            bind: [.text(accountingId.uuidString), .text(inventoryId.uuidString)]
        ) { $0.int(0) }) != nil
    }
}
