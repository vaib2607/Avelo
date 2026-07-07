import Foundation

public struct BOMRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) { self.db = db }

    private static let bomColumns = "id, company_id, assembly_item_id, output_quantity, created_at, updated_at"
    private static let componentColumns = "id, company_id, bom_id, component_item_id, quantity, line_order"

    public func upsertBOM(_ bom: BillOfMaterials) throws {
        try db.execute(
            """
            INSERT INTO avelo_boms
            (id, company_id, assembly_item_id, output_quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(assembly_item_id) DO UPDATE SET
                company_id = excluded.company_id,
                output_quantity = excluded.output_quantity,
                updated_at = excluded.updated_at
            """,
            [
                .text(bom.id.uuidString),
                .text(bom.companyId.uuidString),
                .text(bom.assemblyItemId.uuidString),
                .real(bom.outputQuantity),
                .timestamp(bom.createdAt),
                .timestamp(bom.updatedAt)
            ]
        )
    }

    public func replaceComponents(for bomId: BillOfMaterials.ID, components: [BOMComponent]) throws {
        try db.execute("DELETE FROM avelo_bom_components WHERE bom_id = ?", [.text(bomId.uuidString)])
        for component in components {
            try db.execute(
                """
                INSERT INTO avelo_bom_components
                (id, company_id, bom_id, component_item_id, quantity, line_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(component.id.uuidString),
                    .text(component.companyId.uuidString),
                    .text(component.bomId.uuidString),
                    .text(component.componentItemId.uuidString),
                    .real(component.quantity),
                    .integer(Int64(component.lineOrder))
                ]
            )
        }
    }

    public func loadBOM(companyId: Company.ID, assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        guard let bom = try db.queryOne(
            "SELECT \(Self.bomColumns) FROM avelo_boms WHERE company_id = ? AND assembly_item_id = ? LIMIT 1",
            bind: [.text(companyId.uuidString), .text(assemblyItemId.uuidString)],
            row: { try Self.rowToBOM($0) }
        ) else {
            return nil
        }
        let components = try loadComponents(bomId: bom.id)
        return (bom, components)
    }

    public func loadComponents(bomId: BillOfMaterials.ID) throws -> [BOMComponent] {
        try db.query(
            "SELECT \(Self.componentColumns) FROM avelo_bom_components WHERE bom_id = ? ORDER BY line_order ASC, id ASC",
            bind: [.text(bomId.uuidString)]
        ) { try Self.rowToComponent($0) }
    }

    public func listComponentEdges(companyId: Company.ID) throws -> [(assemblyItemId: InventoryItem.ID, componentItemId: InventoryItem.ID)] {
        try db.query(
            """
            SELECT b.assembly_item_id, c.component_item_id
            FROM avelo_boms b
            JOIN avelo_bom_components c ON c.bom_id = b.id
            WHERE b.company_id = ?
            ORDER BY b.assembly_item_id, c.line_order, c.id
            """,
            bind: [.text(companyId.uuidString)]
        ) {
            (
                try UUIDParsing.required($0.requiredText("assembly_item_id"), field: "avelo_boms.assembly_item_id"),
                try UUIDParsing.required($0.requiredText("component_item_id"), field: "avelo_bom_components.component_item_id")
            )
        }
    }

    public func findBOMByAssemblyItem(companyId: Company.ID, assemblyItemId: InventoryItem.ID) throws -> BillOfMaterials? {
        try db.queryOne(
            "SELECT \(Self.bomColumns) FROM avelo_boms WHERE company_id = ? AND assembly_item_id = ? LIMIT 1",
            bind: [.text(companyId.uuidString), .text(assemblyItemId.uuidString)]
        ) { try Self.rowToBOM($0) }
    }

    private static func rowToBOM(_ row: Row) throws -> BillOfMaterials {
        BillOfMaterials(
            id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_boms.id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_boms.company_id"),
            assemblyItemId: try UUIDParsing.required(row.requiredText("assembly_item_id"), field: "avelo_boms.assembly_item_id"),
            outputQuantity: row.real("output_quantity"),
            createdAt: try row.timestamp("created_at"),
            updatedAt: try row.timestamp("updated_at")
        )
    }

    private static func rowToComponent(_ row: Row) throws -> BOMComponent {
        BOMComponent(
            id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_bom_components.id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_bom_components.company_id"),
            bomId: try UUIDParsing.required(row.requiredText("bom_id"), field: "avelo_bom_components.bom_id"),
            componentItemId: try UUIDParsing.required(row.requiredText("component_item_id"), field: "avelo_bom_components.component_item_id"),
            quantity: row.real("quantity"),
            lineOrder: Int(try row.requiredInt("line_order"))
        )
    }
}
