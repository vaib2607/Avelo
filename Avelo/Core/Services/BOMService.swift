import Foundation

public final class BOMService: Sendable {
    public let db: SQLiteDatabase
    public let repository: BOMRepository
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = BOMRepository(db: db)
        self.companyId = companyId
    }

    public func createBOM(assemblyItemId: InventoryItem.ID,
                          outputQuantity: ExactQuantity,
                          components: [BOMComponent]) throws {
        try persistBOM(
            mode: .create,
            assemblyItemId: assemblyItemId,
            outputQuantity: outputQuantity,
            components: components
        )
    }

    public func updateBOM(assemblyItemId: InventoryItem.ID,
                          outputQuantity: ExactQuantity,
                          components: [BOMComponent]) throws {
        try persistBOM(
            mode: .update,
            assemblyItemId: assemblyItemId,
            outputQuantity: outputQuantity,
            components: components
        )
    }

    public func loadBOM(for assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        try ensureInventoryEnabled(using: db)
        return try repository.loadBOM(companyId: companyId, assemblyItemId: assemblyItemId)
    }

    public func listBOMs() throws -> [BOMRepository.BOMListRow] {
        try ensureInventoryEnabled(using: db)
        return try repository.listBOMs(companyId: companyId)
    }

    private enum PersistenceMode {
        case create
        case update

        var auditReason: String {
            switch self {
            case .create:
                return "Bill of materials recipe setup created."
            case .update:
                return "Bill of materials recipe setup updated."
            }
        }
    }

    private struct BOMAuditSnapshot: Codable, Sendable {
        let bom: BillOfMaterials
        let components: [BOMComponent]
    }

    private func persistBOM(mode: PersistenceMode,
                            assemblyItemId: InventoryItem.ID,
                            outputQuantity: ExactQuantity,
                            components: [BOMComponent]) throws {
        try db.write { tx in
            try ensureInventoryEnabled(using: tx)

            let repo = BOMRepository(db: tx)
            let existing = try repo.findBOMByAssemblyItem(companyId: companyId, assemblyItemId: assemblyItemId)
            switch mode {
            case .create where existing != nil:
                throw AppError.businessRule("A BOM already exists for this assembly item. Use the edit flow to update it.")
            case .update where existing == nil:
                throw AppError.notFound("BOM for the selected assembly item")
            default:
                break
            }

            try validateBOMInput(
                using: tx,
                assemblyItemId: assemblyItemId,
                outputQuantity: outputQuantity,
                components: components
            )

            let beforeSnapshot: BOMAuditSnapshot?
            if let existing {
                beforeSnapshot = BOMAuditSnapshot(
                    bom: existing,
                    components: try repo.loadComponents(bomId: existing.id, companyId: companyId)
                )
            } else {
                beforeSnapshot = nil
            }

            let now = Date()
            let bom = BillOfMaterials(
                id: existing?.id ?? UUID(),
                companyId: companyId,
                assemblyItemId: assemblyItemId,
                outputQuantity: outputQuantity,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            let normalizedComponents = components.enumerated().map { index, component in
                BOMComponent(
                    id: UUID(),
                    companyId: companyId,
                    bomId: bom.id,
                    componentItemId: component.componentItemId,
                    quantity: component.quantity,
                    lineOrder: index
                )
            }

            try assertNoCycles(
                assemblyItemId: assemblyItemId,
                proposedComponents: normalizedComponents,
                repository: repo
            )

            switch mode {
            case .create:
                try repo.insertBOM(bom)
            case .update:
                try repo.updateBOM(bom)
            }
            try repo.replaceComponents(for: bom.id, companyId: companyId, components: normalizedComponents)

            try AuditService(db: tx, companyId: companyId).record(
                action: mode == .create ? .billOfMaterialsCreated : .billOfMaterialsUpdated,
                entityType: "bill_of_materials",
                entityId: bom.id.uuidString,
                snapshotBefore: beforeSnapshot,
                snapshotAfter: BOMAuditSnapshot(bom: bom, components: normalizedComponents),
                reason: mode.auditReason
            )
        }
    }

    private func ensureInventoryEnabled(using database: SQLiteDatabase) throws {
        guard let company = try CompanyRepository(db: database).findById(companyId) else {
            throw AppError.notFound("Company")
        }
        guard company.isInventoryEnabled else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
    }

    private func validateBOMInput(using database: SQLiteDatabase,
                                  assemblyItemId: InventoryItem.ID,
                                  outputQuantity: ExactQuantity,
                                  components: [BOMComponent]) throws {
        guard !outputQuantity.isZero else {
            throw AppError.validation(.init(code: .internal, field: "outputQuantity", message: "Output quantity must be greater than zero."))
        }
        guard !components.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "components", message: "At least one BOM component is required."))
        }
        let inventoryRepository = InventoryRepository(db: database)
        guard let assemblyItem = try inventoryRepository.findItem(id: assemblyItemId),
              assemblyItem.companyId == companyId,
              assemblyItem.isActive else {
            throw AppError.validation(.init(code: .internal, field: "assemblyItemId", message: "Assembly item must belong to this company and be active."))
        }

        var componentItemIds = Set<InventoryItem.ID>()
        for component in components {
            guard component.companyId == companyId else {
                throw AppError.validation(.init(code: .internal, field: "components", message: "BOM components must belong to the active company."))
            }
            guard componentItemIds.insert(component.componentItemId).inserted else {
                throw AppError.validation(.init(code: .internal, field: "componentItemId", message: "A BOM component can only appear once."))
            }
            guard !component.quantity.isZero else {
                throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Component quantity must be greater than zero."))
            }
            guard let item = try inventoryRepository.findItem(id: component.componentItemId),
                  item.companyId == companyId,
                  item.isActive else {
                throw AppError.validation(.init(code: .internal, field: "componentItemId", message: "Component item must belong to this company and be active."))
            }
        }
    }

    private func assertNoCycles(assemblyItemId: InventoryItem.ID,
                                proposedComponents: [BOMComponent],
                                repository: BOMRepository) throws {
        let existingEdges = try repository.listComponentEdges(companyId: companyId)
        var adjacency: [InventoryItem.ID: [InventoryItem.ID]] = [:]
        for edge in existingEdges where edge.assemblyItemId != assemblyItemId {
            adjacency[edge.assemblyItemId, default: []].append(edge.componentItemId)
        }
        adjacency[assemblyItemId] = proposedComponents.map(\.componentItemId)

        var stack: [InventoryItem.ID] = []
        var visiting = Set<InventoryItem.ID>()
        var visited = Set<InventoryItem.ID>()

        func dfs(_ itemId: InventoryItem.ID) throws {
            if visiting.contains(itemId) {
                guard let startIndex = stack.firstIndex(of: itemId) else {
                    throw AppError.businessRule("Circular BOM detected.")
                }
                let cycle = Array(stack[startIndex...]) + [itemId]
                throw AppError.businessRule("Circular BOM detected: " + cycle.map(\.uuidString).joined(separator: " -> "))
            }
            if visited.contains(itemId) { return }
            visiting.insert(itemId)
            stack.append(itemId)
            for child in adjacency[itemId] ?? [] {
                try dfs(child)
            }
            _ = stack.popLast()
            visiting.remove(itemId)
            visited.insert(itemId)
        }

        try dfs(assemblyItemId)
    }
}
