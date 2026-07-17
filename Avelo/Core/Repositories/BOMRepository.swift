import Foundation

public struct BOMRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) { self.db = db }

<<<<<<< HEAD
    private static let bomColumns = "id, company_id, assembly_item_id, output_quantity_numerator, output_quantity_denominator, created_at, updated_at"
    private static let componentColumns = "id, company_id, bom_id, component_item_id, quantity_numerator, quantity_denominator, line_order"

    public func insertBOM(_ bom: BillOfMaterials) throws {
        try db.execute(
            """
            INSERT INTO avelo_boms
            (id, company_id, assembly_item_id, output_quantity,
             output_quantity_numerator, output_quantity_denominator, created_at, updated_at)
            VALUES (?, ?, ?, (? * 1.0 / ?), ?, ?, ?, ?)
=======
    public func upsertBOM(_ bom: BillOfMaterials) throws {
        try db.execute(
            """
            INSERT INTO avelo_boms (id, company_id, assembly_item_id, output_quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(company_id, assembly_item_id) DO UPDATE SET
                output_quantity = excluded.output_quantity,
                updated_at = excluded.updated_at
>>>>>>> origin/main
            """,
            [
                .text(bom.id.uuidString),
                .text(bom.companyId.uuidString),
                .text(bom.assemblyItemId.uuidString),
<<<<<<< HEAD
                .integer(bom.outputQuantity.numerator),
                .integer(bom.outputQuantity.denominator),
                .integer(bom.outputQuantity.numerator),
                .integer(bom.outputQuantity.denominator),
=======
                .real(bom.outputQuantity),
>>>>>>> origin/main
                .timestamp(bom.createdAt),
                .timestamp(bom.updatedAt)
            ]
        )
    }

<<<<<<< HEAD
    public func updateBOM(_ bom: BillOfMaterials) throws {
        try db.execute(
            """
            UPDATE avelo_boms
               SET output_quantity = (? * 1.0 / ?),
                   output_quantity_numerator = ?,
                   output_quantity_denominator = ?,
                   updated_at = ?
             WHERE id = ?
               AND company_id = ?
               AND assembly_item_id = ?
            """,
            [
                .integer(bom.outputQuantity.numerator),
                .integer(bom.outputQuantity.denominator),
                .integer(bom.outputQuantity.numerator),
                .integer(bom.outputQuantity.denominator),
                .timestamp(bom.updatedAt),
                .text(bom.id.uuidString),
                .text(bom.companyId.uuidString),
                .text(bom.assemblyItemId.uuidString)
            ]
        )
    }

    public func replaceComponents(for bomId: BillOfMaterials.ID,
                                  companyId: Company.ID,
                                  components: [BOMComponent]) throws {
        guard components.allSatisfy({ $0.bomId == bomId && $0.companyId == companyId }) else {
            throw AppError.businessRule("BOM component ownership does not match the recipe being updated.")
        }

        try db.execute(
            "DELETE FROM avelo_bom_components WHERE bom_id = ? AND company_id = ?",
            [.text(bomId.uuidString), .text(companyId.uuidString)]
        )
        for component in components {
            try db.execute(
                """
                INSERT INTO avelo_bom_components
                (id, company_id, bom_id, component_item_id, quantity,
                 quantity_numerator, quantity_denominator, line_order)
                VALUES (?, ?, ?, ?, (? * 1.0 / ?), ?, ?, ?)
                """,
                [
                    .text(component.id.uuidString),
                    .text(component.companyId.uuidString),
                    .text(component.bomId.uuidString),
                    .text(component.componentItemId.uuidString),
                    .integer(component.quantity.numerator),
                    .integer(component.quantity.denominator),
                    .integer(component.quantity.numerator),
                    .integer(component.quantity.denominator),
                    .integer(Int64(component.lineOrder))
=======
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
>>>>>>> origin/main
                ]
            )
        }
    }

    public func loadBOM(companyId: Company.ID, assemblyItemId: InventoryItem.ID) throws -> (BillOfMaterials, [BOMComponent])? {
        guard let bom = try db.queryOne(
<<<<<<< HEAD
            "SELECT \(Self.bomColumns) FROM avelo_boms WHERE company_id = ? AND assembly_item_id = ? LIMIT 1",
            bind: [.text(companyId.uuidString), .text(assemblyItemId.uuidString)],
            row: { try Self.rowToBOM($0) }
        ) else {
            return nil
        }
        let components = try loadComponents(bomId: bom.id, companyId: companyId)
        return (bom, components)
    }

    public func loadComponents(bomId: BillOfMaterials.ID, companyId: Company.ID) throws -> [BOMComponent] {
        try db.query(
            "SELECT \(Self.componentColumns) FROM avelo_bom_components WHERE bom_id = ? AND company_id = ? ORDER BY line_order ASC, id ASC",
            bind: [.text(bomId.uuidString), .text(companyId.uuidString)]
        ) { try Self.rowToComponent($0) }
    }

    public func listComponentEdges(companyId: Company.ID) throws -> [(assemblyItemId: InventoryItem.ID, componentItemId: InventoryItem.ID)] {
        try db.query(
            """
            SELECT b.assembly_item_id, c.component_item_id
            FROM avelo_boms b
            JOIN avelo_bom_components c ON c.bom_id = b.id
            WHERE b.company_id = ? AND c.company_id = b.company_id
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

    public struct BOMListRow: Identifiable, Sendable {
        public let bom: BillOfMaterials
        public let assemblyItemName: String
        public let componentCount: Int
        public let assemblyItemIsActive: Bool
        public let invalidComponentCount: Int
        public var id: BillOfMaterials.ID { bom.id }

        public var isEditable: Bool {
            assemblyItemIsActive && componentCount > 0 && invalidComponentCount == 0
        }

        public var editingBlockReason: String? {
            if !assemblyItemIsActive {
                return "The assembly item is archived. Reactivate it before editing this BOM."
            }
            if componentCount == 0 {
                return "This BOM has no components and cannot be edited safely."
            }
            if invalidComponentCount > 0 {
                return "One or more component items are archived or unavailable. Reactivate them before editing this BOM."
            }
            return nil
        }
    }

    public func listBOMs(companyId: Company.ID) throws -> [BOMListRow] {
        try db.query(
            """
            SELECT b.id, b.company_id, b.assembly_item_id,
                   b.output_quantity_numerator, b.output_quantity_denominator,
                   b.created_at, b.updated_at,
                   i.name AS assembly_item_name,
                   i.is_active AS assembly_item_is_active,
                   (SELECT COUNT(*) FROM avelo_bom_components c WHERE c.bom_id = b.id AND c.company_id = b.company_id) AS component_count,
                   (
                       SELECT COUNT(*)
                       FROM avelo_bom_components c
                       LEFT JOIN avelo_inventory_items component
                         ON component.id = c.component_item_id
                       WHERE c.bom_id = b.id
                         AND (
                             c.company_id != b.company_id
                             OR component.id IS NULL
                             OR component.company_id != b.company_id
                             OR component.is_active != 1
                         )
                   ) AS invalid_component_count
            FROM avelo_boms b
            JOIN avelo_inventory_items i ON i.id = b.assembly_item_id AND i.company_id = b.company_id
            WHERE b.company_id = ?
            ORDER BY i.name COLLATE NOCASE
            """,
            bind: [.text(companyId.uuidString)]
        ) { row in
            BOMListRow(
                bom: try Self.rowToBOM(row),
                assemblyItemName: try row.requiredText("assembly_item_name"),
                componentCount: Int(try row.requiredInt("component_count")),
                assemblyItemIsActive: try row.requiredBool("assembly_item_is_active"),
                invalidComponentCount: Int(try row.requiredInt("invalid_component_count"))
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
            outputQuantity: try ExactQuantity(
                numerator: row.requiredInt("output_quantity_numerator"),
                denominator: row.requiredInt("output_quantity_denominator")
            ),
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
            quantity: try ExactQuantity(
                numerator: row.requiredInt("quantity_numerator"),
                denominator: row.requiredInt("quantity_denominator")
            ),
            lineOrder: Int(try row.requiredInt("line_order"))
        )
=======
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
>>>>>>> origin/main
    }
}
