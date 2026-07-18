import Foundation

/// Capitalizes an explicitly chosen canonical accounting cost into inbound
/// stock. UI decides which cost is eligible; this service makes the chosen
/// allocation deterministic, atomic, and auditable.
public final class InventoryCostAllocationService: Sendable {
    public enum CapitalizationKind: String, Sendable, Codable {
        case freight
        case irrecoverableTax
    }

    public struct Request: Sendable {
        public let accountingId: LedgerLine.ID
        public let inventoryIds: [StockMovement.ID]
        public let kind: CapitalizationKind
        public let reason: String?

        public init(accountingId: LedgerLine.ID,
                    inventoryIds: [StockMovement.ID],
                    kind: CapitalizationKind,
                    reason: String? = nil) {
            self.accountingId = accountingId
            self.inventoryIds = inventoryIds
            self.kind = kind
            self.reason = reason
        }
    }

    public struct Result: Sendable {
        public let allocations: [InventoryCostAllocation]
    }

    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
    }

    public func allocate(_ request: Request) throws -> Result {
        var result: Result?
        try db.write { tx in
            result = try Self.allocateInCurrentTransaction(request, db: tx, companyId: companyId)
        }
        guard let result else {
            throw AppError.unexpected("Inventory cost allocation did not produce a result.")
        }
        ReportService.invalidateCache(companyId: companyId)
        return result
    }

    static func allocateInCurrentTransaction(_ request: Request,
                                             db: SQLiteDatabase,
                                             companyId: Company.ID) throws -> Result {
        guard !request.inventoryIds.isEmpty,
              Set(request.inventoryIds).count == request.inventoryIds.count else {
            throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "inventoryIds", message: "Choose one or more distinct inbound inventory movements."))
        }

        let accounting = LedgerLineRepository(db: db)
        guard let source = try accounting.findById(request.accountingId), source.companyId == companyId else {
            throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "accountingId", message: "Cost source is missing or belongs to another company."))
        }
        // Recoverable GST is never capitalized. Tax-coded lines are not
        // silently treated as freight; callers must select an explicitly
        // irrecoverable-tax source with no recoverable GST tax code.
        if let tax = source.taxCode?.uppercased(), tax.contains("GST") || tax.contains("CGST") || tax.contains("SGST") || tax.contains("IGST") {
            throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "accountingId", message: "Recoverable GST cannot be capitalized into inventory."))
        }
        guard source.amountPaise > 0 else {
            throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "accountingId", message: "Cost source amount must be positive."))
        }
        guard let sourceVoucher = try VoucherRepository(db: db).findById(source.voucherId), sourceVoucher.companyId == companyId else {
            throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "accountingId", message: "Cost source voucher is unavailable."))
        }
        _ = try FiscalLockChecker(db: db).assertDateOpen(sourceVoucher.date, companyId: companyId, mutationLabel: "Inventory cost allocation")

        let inventory = InventoryRepository(db: db)
        let allocationRepo = InventoryCostAllocationRepository(db: db)
        var movements: [StockMovement] = []
        for id in request.inventoryIds {
            guard let movement = try inventory.findMovement(id: id), movement.companyId == companyId, movement.movementType == .stockIn else {
                throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "inventoryIds", message: "Landed cost may be allocated only to company-owned inbound movements."))
            }
            _ = try FiscalLockChecker(db: db).assertDateOpen(movement.date, companyId: companyId, mutationLabel: "Inventory cost allocation")
            guard !(try allocationRepo.hasAllocation(accountingId: source.id, inventoryId: movement.id)) else {
                throw AppError.validation(.init(code: .inventoryCostSourceInvalid, field: "inventoryIds", message: "This source has already been allocated to one selected movement."))
            }
            movements.append(movement)
        }

        let ordered = movements.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let totalQuantity = try ordered.reduce(into: ExactQuantity.whole(0)) {
            $0 = try ExactQuantity.add($0, $1.quantity, context: "summing landed-cost allocation quantity")
        }
        var remaining = source.amountPaise
        var allocations: [InventoryCostAllocation] = []
        for (index, movement) in ordered.enumerated() {
            let amount: Int64
            if index == ordered.indices.last {
                amount = remaining
            } else {
                amount = try proratedFloor(amount: source.amountPaise, quantity: movement.quantity, total: totalQuantity)
            }
            guard amount > 0 else { continue }
            remaining = try CheckedMath.subtract(remaining, amount, context: "distributing landed-cost residual paise")
            let allocation = try InventoryCostAllocation(companyId: companyId, accountingId: source.id, inventoryId: movement.id, allocatedPaise: amount)
            try allocationRepo.insert(allocation)
            try inventory.addLandedCostPaise(amount, to: movement.id, companyId: companyId)
            allocations.append(allocation)
        }
        guard remaining == 0, !allocations.isEmpty else {
            throw AppError.businessRule("Landed-cost allocation did not consume the selected accounting amount.")
        }
        try AuditService(db: db, companyId: companyId).record(
            action: .inventoryCostAllocated,
            entityType: "inventory_cost_allocation",
            entityId: source.id.uuidString,
            snapshotAfter: allocations,
            reason: request.reason ?? request.kind.rawValue
        )
        return .init(allocations: allocations)
    }

    private static func proratedFloor(amount: Int64, quantity: ExactQuantity, total: ExactQuantity) throws -> Int64 {
        let first = try CheckedMath.multiply(amount, quantity.numerator, context: "allocating landed cost")
        let numerator = try CheckedMath.multiply(first, total.denominator, context: "allocating landed cost")
        let denominator = try CheckedMath.multiply(quantity.denominator, total.numerator, context: "allocating landed cost")
        guard denominator > 0 else {
            throw AppError.validation(.init(code: .arithmeticOverflow, field: "quantity", message: "Landed-cost allocation quantity is invalid."))
        }
        return numerator / denominator
    }
}
