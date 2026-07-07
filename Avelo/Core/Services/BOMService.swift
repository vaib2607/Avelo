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

    public func saveBOM(assemblyItemId: InventoryItem.ID,
                        outputQuantity: Double,
                        components: [BOMComponent]) throws {
        try ensureInventoryEnabled()
        try validateBOMInput(assemblyItemId: assemblyItemId, outputQuantity: outputQuantity, components: components)

        let existing = try repository.findBOMByAssemblyItem(companyId: companyId, assemblyItemId: assemblyItemId)
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
                id: component.id,
                companyId: companyId,
                bomId: bom.id,
                componentItemId: component.componentItemId,
                quantity: component.quantity,
                lineOrder: index
            )
        }

        try assertNoCycles(assemblyItemId: assemblyItemId, proposedComponents: normalizedComponents)

        try db.write { tx in
            let repo = BOMRepository(db: tx)
            try repo.upsertBOM(bom)
            try repo.replaceComponents(for: bom.id, components: normalizedComponents)
        }
    }

    public func loadBOM(for assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        try ensureInventoryEnabled()
        return try repository.loadBOM(companyId: companyId, assemblyItemId: assemblyItemId)
    }

    private func ensureInventoryEnabled() throws {
        guard try CompanyRepository(db: db).findById(companyId)?.isInventoryEnabled == true else {
            throw AppError.featureUnavailable("Inventory is disabled for this company.")
        }
    }

    private func validateBOMInput(assemblyItemId: InventoryItem.ID,
                                  outputQuantity: Double,
                                  components: [BOMComponent]) throws {
        guard outputQuantity.isFinite, outputQuantity > 0 else {
            throw AppError.validation(.init(code: .internal, field: "outputQuantity", message: "Output quantity must be greater than zero."))
        }
        guard !components.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "components", message: "At least one BOM component is required."))
        }
        guard let assemblyItem = try InventoryRepository(db: db).findItem(id: assemblyItemId),
              assemblyItem.companyId == companyId,
              assemblyItem.isActive else {
            throw AppError.validation(.init(code: .internal, field: "assemblyItemId", message: "Assembly item must belong to this company and be active."))
        }
        for component in components {
            guard component.companyId == companyId else {
                throw AppError.validation(.init(code: .internal, field: "components", message: "BOM components must belong to the active company."))
            }
            guard component.quantity.isFinite, component.quantity > 0 else {
                throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Component quantity must be greater than zero."))
            }
            guard let item = try InventoryRepository(db: db).findItem(id: component.componentItemId),
                  item.companyId == companyId,
                  item.isActive else {
                throw AppError.validation(.init(code: .internal, field: "componentItemId", message: "Component item must belong to this company and be active."))
            }
        }
    }

    private func assertNoCycles(assemblyItemId: InventoryItem.ID,
                                proposedComponents: [BOMComponent]) throws {
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
