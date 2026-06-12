import Foundation

public struct BOMRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) { self.db = db }

    public func upsertBOM(_ bom: BillOfMaterials) throws {
        try db.execute(
            """
            INSERT INTO avelo_boms (id, company_id, assembly_item_id, output_quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(company_id, assembly_item_id) DO UPDATE SET
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

    public func upsertComponents(_ components: [BOMComponent]) throws {
        for c in components {
            try db.execute(
                """
                INSERT INTO avelo_bom_components (id, company_id, bom_id, component_item_id, quantity, line_order)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    component_item_id = excluded.component_item_id,
                    quantity = excluded.quantity,
                    line_order = excluded.line_order
                """,
                [
                    .text(c.id.uuidString),
                    .text(c.companyId.uuidString),
                    .text(c.bomId.uuidString),
                    .text(c.componentItemId.uuidString),
                    .real(c.quantity),
                    .integer(Int64(c.lineOrder))
                ]
            )
        }
    }

    public func loadBOM(companyId: Company.ID, assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        guard let bom = try db.queryOne(
            "SELECT id, company_id, assembly_item_id, output_quantity, created_at, updated_at FROM avelo_boms WHERE company_id = ? AND assembly_item_id = ?",
            bind: [.text(companyId.uuidString), .text(assemblyItemId.uuidString)],
            row: { r in
            BillOfMaterials(
                id: try UUIDParsing.required(r.text("id"), field: "avelo_boms.id"),
                companyId: try UUIDParsing.required(r.text("company_id"), field: "avelo_boms.company_id"),
                assemblyItemId: try UUIDParsing.required(r.text("assembly_item_id"), field: "avelo_boms.assembly_item_id"),
                outputQuantity: r.real("output_quantity"),
                createdAt: r.timestamp("created_at"),
                updatedAt: r.timestamp("updated_at")
            )
            }
        ) else { return nil }
        let components = try db.query(
            "SELECT id, company_id, bom_id, component_item_id, quantity, line_order FROM avelo_bom_components WHERE bom_id = ? ORDER BY line_order",
            bind: [.text(bom.id.uuidString)]
        ) { r in
            BOMComponent(
                id: try UUIDParsing.required(r.text("id"), field: "avelo_bom_components.id"),
                companyId: try UUIDParsing.required(r.text("company_id"), field: "avelo_bom_components.company_id"),
                bomId: try UUIDParsing.required(r.text("bom_id"), field: "avelo_bom_components.bom_id"),
                componentItemId: try UUIDParsing.required(r.text("component_item_id"), field: "avelo_bom_components.component_item_id"),
                quantity: r.real("quantity"),
                lineOrder: Int(r.int("line_order"))
            )
        }
        return (bom, components)
    }
}
