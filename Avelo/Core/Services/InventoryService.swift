import Foundation

public final class InventoryService: Sendable {

    public struct RecalculationPublication: Sendable, Equatable {
        public enum Phase: String, Sendable, Equatable {
            case published
        }

        public let itemId: InventoryItem.ID
        public let effectiveFromDate: Date
        public let affectedMovementIds: [StockMovement.ID]
        public let phase: Phase
        public let publishedAt: Date

        public var affectedMovementCount: Int { affectedMovementIds.count }
    }

    public struct ReversalResult: Sendable, Equatable {
        public let originalMovement: StockMovement
        public let reversalMovement: StockMovement
        public let publication: RecalculationPublication
    }

    public struct ReplacementResult: Sendable, Equatable {
        public let originalMovement: StockMovement
        public let reversalMovement: StockMovement
        public let replacementMovement: StockMovement
        public let publication: RecalculationPublication
    }

    public let db: SQLiteDatabase
    public let repository: InventoryRepository
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = InventoryRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public func listItems(includeArchived: Bool = false) throws -> [InventoryItem] {
        try ensureInventoryEnabled()
        return try repository.listItems(companyId: companyId, includeArchived: includeArchived)
    }

    public func listItems(includeArchived: Bool = false, limit: Int, offset: Int = 0) throws -> [InventoryItem] {
        try ensureInventoryEnabled()
        return try repository.listItems(companyId: companyId, includeArchived: includeArchived, limit: limit, offset: offset)
    }

    public func listItems(filter: InventoryRepository.ItemFilter) throws -> [InventoryItem] {
        try ensureInventoryEnabled()
        return try repository.listItems(filter: filter)
    }

    public func countItems(filter: InventoryRepository.ItemFilter) throws -> Int {
        try ensureInventoryEnabled()
        return try repository.countItems(filter: filter)
    }

    public func findItem(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try ensureInventoryEnabled()
        return try repository.findItem(id: id)
    }

    public func createItem(code: String,
                           name: String,
                           unit: String,
                           alternateUnit: String? = nil,
                           baseUnitsPerAlternateUnit: ExactQuantity? = nil,
                           valuationMethod: ValuationMethod = .fifo) throws -> InventoryItem {
        try ensureInventoryEnabled()
        let trimmedAlternateUnit = alternateUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAlternateUnit = !(trimmedAlternateUnit?.isEmpty ?? true)
        if hasAlternateUnit != (baseUnitsPerAlternateUnit != nil) {
            throw AppError.validation(.init(code: .internal, field: "alternateUnit", message: "Alternate unit and conversion ratio must both be provided."))
        }
        let item = InventoryItem(
            companyId: companyId,
            code: code,
            name: name,
            unit: unit,
            alternateUnit: hasAlternateUnit ? trimmedAlternateUnit : nil,
            baseUnitsPerAlternateUnit: baseUnitsPerAlternateUnit,
            valuationMethod: valuationMethod
        )
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.insertItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemCreated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
        return item
    }

    public func updateItem(_ item: InventoryItem) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.updateItem(item)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemUpdated,
                entityType: "inventory_item",
                entityId: item.id.uuidString,
                snapshotAfter: item
            )
        }
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.archiveItem(id)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemDisabled,
                entityType: "inventory_item",
                entityId: id.uuidString
            )
        }
    }

    public func recordMovement(itemId: InventoryItem.ID,
                               date: Date,
                               type: InventoryItem.MovementType,
                               quantity: Int64,
                               ratePaise: Int64,
                               voucherId: Voucher.ID? = nil,
                               notes: String? = nil) throws -> RecalculationPublication {
        try recordMovement(
            itemId: itemId,
            date: date,
            type: type,
            quantity: try ExactQuantity.whole(quantity),
            ratePaise: ratePaise,
            voucherId: voucherId,
            enteredUnit: nil,
            notes: notes
        )
    }

    public func recordMovement(itemId: InventoryItem.ID,
                               date: Date,
                               type: InventoryItem.MovementType,
                               quantity: ExactQuantity,
                               ratePaise: Int64,
                               voucherId: Voucher.ID? = nil,
                               enteredUnit: String? = nil,
                               notes: String? = nil) throws -> RecalculationPublication {
        try ensureInventoryEnabled()
        _ = try FiscalLockChecker(db: db).assertDateOpen(date, companyId: companyId, mutationLabel: "Stock movement date")
        guard let item = try repository.findItem(id: itemId), item.companyId == companyId else {
            throw AppError.notFound("Inventory item")
        }
        let baseQuantity = try convertToBaseQuantity(quantity, enteredUnit: enteredUnit, item: item)
        let movement = StockMovement(
            id: UUID(),
            companyId: companyId,
            itemId: itemId,
            date: date,
            movementType: type,
            quantity: baseQuantity,
            unitCostPaise: ratePaise,
            totalValuePaise: type == .stockOut ? 0 : try baseQuantity.multiplied(byUnitCostPaise: ratePaise, context: "calculating stock movement total value"),
            voucherId: voucherId,
            enteredUnit: enteredUnit,
            reason: notes
        )
        var publication: RecalculationPublication?
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            let onHand = try repo.runningBalance(itemId: itemId, asOf: date).onHandQuantity
            let currentOnHand = onHand.isZero ? try ExactQuantity.whole(0) : onHand.magnitude
            let authoritativeMovement = try authoritativeMovementForInsertion(
                draft: movement,
                item: item,
                repository: repo
            )
            let validation = StockMovementValidator().validate(StockMovementValidator.Input(
                itemId: itemId,
                date: date,
                movementType: type,
                quantity: baseQuantity,
                unitCostPaise: ratePaise,
                totalValuePaise: authoritativeMovement.totalValuePaise,
                currentOnHandQty: currentOnHand
            ))
            if case .invalid(let errs) = validation {
                throw AppError.validation(errs[0])
            }
            try repo.insertMovement(authoritativeMovement)
            publication = try republishAuthoritativeValuation(
                item: item,
                effectiveFromDate: date,
                repository: repo
            )
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockMovementPosted,
                entityType: "stock_movement",
                entityId: authoritativeMovement.id.uuidString,
                snapshotAfter: authoritativeMovement
            )
        }
        return publication ?? .init(itemId: itemId, effectiveFromDate: date, affectedMovementIds: [], phase: .published, publishedAt: Date())
    }

    public func reverseMovement(_ movementId: StockMovement.ID, reason: String? = nil) throws -> ReversalResult {
        try ensureInventoryEnabled()
        var result: ReversalResult?
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            guard let original = try repo.findMovement(id: movementId), original.companyId == companyId else {
                throw AppError.notFound("Stock movement")
            }
            _ = try FiscalLockChecker(db: tx).assertDateOpen(original.date, companyId: companyId, mutationLabel: "Stock movement date")
            let item = try requireItem(id: original.itemId, repository: repo)
            let reversalType = oppositeMovementType(for: original.movementType)
            let reversalReason = buildReversalReason(originalMovementId: original.id, reason: reason)
            let draftReversal = StockMovement(
                companyId: companyId,
                itemId: original.itemId,
                date: original.date,
                movementType: reversalType,
                quantity: original.quantity,
                unitCostPaise: original.unitCostPaise,
                totalValuePaise: reversalType == .stockIn ? original.totalValuePaise : 0,
                voucherId: original.voucherId,
                enteredUnit: original.enteredUnit,
                reversedMovementId: reversalType == .stockOut ? original.id : original.reversedMovementId ?? original.id,
                referenceVoucherNumber: original.referenceVoucherNumber,
                reason: reversalReason
            )
            let authoritativeReversal = try authoritativeMovementForInsertion(
                draft: draftReversal,
                item: item,
                repository: repo
            )
            let onHand = try repo.runningBalance(itemId: original.itemId, asOf: original.date).onHandQuantity
            let currentOnHand = onHand.isZero ? try ExactQuantity.whole(0) : onHand.magnitude
            let validation = StockMovementValidator().validate(.init(
                itemId: original.itemId,
                date: original.date,
                movementType: authoritativeReversal.movementType,
                quantity: authoritativeReversal.quantity,
                unitCostPaise: authoritativeReversal.unitCostPaise,
                totalValuePaise: authoritativeReversal.totalValuePaise,
                currentOnHandQty: currentOnHand,
                allowAuthoritativeTotalOverride: authoritativeReversal.reversedMovementId != nil && authoritativeReversal.movementType != .stockOut
            ))
            if case .invalid(let errors) = validation {
                throw AppError.validation(errors[0])
            }
            try repo.insertMovement(authoritativeReversal)
            let publication = try republishAuthoritativeValuation(
                item: item,
                effectiveFromDate: original.date,
                repository: repo
            )
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockMovementReversed,
                entityType: "stock_movement",
                entityId: authoritativeReversal.id.uuidString,
                snapshotBefore: original,
                snapshotAfter: authoritativeReversal,
                reason: reason
            )
            result = .init(originalMovement: original, reversalMovement: authoritativeReversal, publication: publication)
        }
        guard let result else {
            throw AppError.unexpected("Stock movement reversal did not complete.")
        }
        return result
    }

    public func replaceMovement(_ movementId: StockMovement.ID,
                                date: Date,
                                type: InventoryItem.MovementType,
                                quantity: ExactQuantity,
                                ratePaise: Int64,
                                voucherId: Voucher.ID? = nil,
                                enteredUnit: String? = nil,
                                notes: String? = nil,
                                reason: String? = nil) throws -> ReplacementResult {
        try ensureInventoryEnabled()
        _ = try FiscalLockChecker(db: db).assertDateOpen(date, companyId: companyId, mutationLabel: "Stock movement date")
        var result: ReplacementResult?
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            guard let original = try repo.findMovement(id: movementId), original.companyId == companyId else {
                throw AppError.notFound("Stock movement")
            }
            _ = try FiscalLockChecker(db: tx).assertDateOpen(original.date, companyId: companyId, mutationLabel: "Stock movement date")
            let item = try requireItem(id: original.itemId, repository: repo)
            let reversalType = oppositeMovementType(for: original.movementType)
            let reversalReason = buildReplacementReversalReason(originalMovementId: original.id, reason: reason)
            let draftReversal = StockMovement(
                companyId: companyId,
                itemId: original.itemId,
                date: original.date,
                movementType: reversalType,
                quantity: original.quantity,
                unitCostPaise: original.unitCostPaise,
                totalValuePaise: reversalType == .stockIn ? original.totalValuePaise : 0,
                voucherId: original.voucherId,
                enteredUnit: original.enteredUnit,
                reversedMovementId: reversalType == .stockOut ? original.id : original.reversedMovementId ?? original.id,
                referenceVoucherNumber: original.referenceVoucherNumber,
                reason: reversalReason
            )
            let authoritativeReversal = try authoritativeMovementForInsertion(draft: draftReversal, item: item, repository: repo)
            let replacementQuantity = try convertToBaseQuantity(quantity, enteredUnit: enteredUnit, item: item)
            let draftReplacement = StockMovement(
                companyId: companyId,
                itemId: original.itemId,
                date: date,
                movementType: type,
                quantity: replacementQuantity,
                unitCostPaise: ratePaise,
                totalValuePaise: type == .stockOut ? 0 : try replacementQuantity.multiplied(byUnitCostPaise: ratePaise, context: "calculating stock movement replacement total value"),
                voucherId: voucherId ?? original.voucherId,
                enteredUnit: enteredUnit,
                referenceVoucherNumber: original.referenceVoucherNumber,
                reason: notes
            )
            let authoritativeReplacement = try authoritativeMovementForInsertion(draft: draftReplacement, item: item, repository: repo, additionalMovements: [authoritativeReversal])

            let earliestDate = min(original.date, date)
            let onHand = try repo.runningBalance(itemId: original.itemId, asOf: earliestDate).onHandQuantity
            let currentOnHand = onHand.isZero ? try ExactQuantity.whole(0) : onHand.magnitude
            for movement in [authoritativeReversal, authoritativeReplacement] {
                let validation = StockMovementValidator().validate(.init(
                    itemId: original.itemId,
                    date: movement.date,
                    movementType: movement.movementType,
                    quantity: movement.quantity,
                    unitCostPaise: movement.unitCostPaise,
                    totalValuePaise: movement.totalValuePaise,
                    currentOnHandQty: currentOnHand,
                    allowAuthoritativeTotalOverride: movement.reversedMovementId != nil && movement.movementType != .stockOut
                ))
                if case .invalid(let errors) = validation {
                    throw AppError.validation(errors[0])
                }
            }

            try repo.insertMovement(authoritativeReversal)
            try repo.insertMovement(authoritativeReplacement)
            let publication = try republishAuthoritativeValuation(
                item: item,
                effectiveFromDate: earliestDate,
                repository: repo
            )
            let audit = AuditService(db: tx, companyId: companyId)
            try audit.record(
                action: .stockMovementReversed,
                entityType: "stock_movement",
                entityId: authoritativeReversal.id.uuidString,
                snapshotBefore: original,
                snapshotAfter: authoritativeReversal,
                reason: reason
            )
            try audit.record(
                action: .stockMovementPosted,
                entityType: "stock_movement",
                entityId: authoritativeReplacement.id.uuidString,
                snapshotAfter: authoritativeReplacement,
                reason: reason
            )
            result = .init(
                originalMovement: original,
                reversalMovement: authoritativeReversal,
                replacementMovement: authoritativeReplacement,
                publication: publication
            )
        }
        guard let result else {
            throw AppError.unexpected("Stock movement replacement did not complete.")
        }
        return result
    }

    private func convertToBaseQuantity(_ quantity: ExactQuantity,
                                       enteredUnit: String?,
                                       item: InventoryItem) throws -> ExactQuantity {
        guard let enteredUnit = enteredUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !enteredUnit.isEmpty else {
            return quantity
        }
        if enteredUnit.caseInsensitiveCompare(item.unit) == .orderedSame {
            return quantity
        }
        guard let definition = item.alternateUnitDefinition else {
            throw AppError.validation(.init(code: .internal, field: "enteredUnit", message: "This item does not define an alternate unit."))
        }
        guard enteredUnit.caseInsensitiveCompare(definition.alternateUnit) == .orderedSame else {
            throw AppError.validation(.init(code: .internal, field: "enteredUnit", message: "Entered unit does not match the item UOM definition."))
        }
        return try definition.convertToBaseUnits(quantity)
    }

    public func stockAsOf(itemId: InventoryItem.ID, date: Date) throws -> InventoryRepository.ItemBalance {
        try ensureInventoryEnabled()
        return try repository.runningBalance(itemId: itemId, asOf: date)
    }

    public func linkItemToAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
        try ensureInventoryEnabled()
        try db.write { tx in
            let repo = InventoryRepository(db: tx)
            try repo.setItemAccount(itemId: itemId, accountId: accountId)
            try AuditService(db: tx, companyId: companyId).record(
                action: .stockItemUpdated,
                entityType: "inventory_item",
                entityId: itemId.uuidString
            )
        }
    }

    private func ensureInventoryEnabled() throws {
        guard let company = try CompanyRepository(db: db).findById(companyId) else {
            throw AppError.notFound("Company")
        }
        guard company.isInventoryEnabled else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
    }

    private func authoritativeMovementForInsertion(draft: StockMovement,
                                                   item: InventoryItem,
                                                   repository: InventoryRepository,
                                                   additionalMovements: [StockMovement] = []) throws -> StockMovement {
        var movement = draft
        guard movement.movementType == .stockOut else {
            return movement
        }
        let priorMovements = try repository.listMovementsChronologically(companyId: companyId, itemId: movement.itemId, asOf: movement.date)
        let replay = try InventoryValuationEngine().replay(
            movements: priorMovements + additionalMovements + [movement],
            valuationMethod: item.valuationMethod
        )
        guard let authoritative = replay.valuedMovements.last(where: { $0.movement.id == movement.id })?.authoritativeTotalValuePaise else {
            throw AppError.businessRule("Unable to determine authoritative stock-out valuation.")
        }
        movement.totalValuePaise = authoritative
        return movement
    }

    private func republishAuthoritativeValuation(item: InventoryItem,
                                                 effectiveFromDate: Date,
                                                 repository: InventoryRepository) throws -> RecalculationPublication {
        let movements = try repository.listMovementsChronologically(companyId: companyId, itemId: item.id)
        let replay = try InventoryValuationEngine().replay(movements: movements, valuationMethod: item.valuationMethod)
        var affectedMovementIds: [StockMovement.ID] = []
        for valued in replay.valuedMovements where valued.movement.date >= effectiveFromDate {
            if valued.movement.totalValuePaise != valued.authoritativeTotalValuePaise {
                try repository.updateMovementTotalValue(
                    id: valued.movement.id,
                    companyId: companyId,
                    totalValuePaise: valued.authoritativeTotalValuePaise
                )
                affectedMovementIds.append(valued.movement.id)
            }
        }
        return .init(
            itemId: item.id,
            effectiveFromDate: effectiveFromDate,
            affectedMovementIds: affectedMovementIds,
            phase: .published,
            publishedAt: Date()
        )
    }

    private func requireItem(id: InventoryItem.ID, repository: InventoryRepository) throws -> InventoryItem {
        guard let item = try repository.findItem(id: id), item.companyId == companyId else {
            throw AppError.notFound("Inventory item")
        }
        return item
    }

    private func oppositeMovementType(for movementType: MovementType) -> MovementType {
        switch movementType {
        case .stockIn, .adjustment:
            return .stockOut
        case .stockOut:
            return .stockIn
        }
    }

    private func buildReversalReason(originalMovementId: StockMovement.ID, reason: String?) -> String {
        let suffix = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix, !suffix.isEmpty {
            return "Reversal of movement \(originalMovementId.uuidString): \(suffix)"
        }
        return "Reversal of movement \(originalMovementId.uuidString)"
    }

    private func buildReplacementReversalReason(originalMovementId: StockMovement.ID, reason: String?) -> String {
        let suffix = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix, !suffix.isEmpty {
            return "Replacement reversal of movement \(originalMovementId.uuidString): \(suffix)"
        }
        return "Replacement reversal of movement \(originalMovementId.uuidString)"
    }
}
