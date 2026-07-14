import Foundation

/// Moves BOM quantities off legacy REAL storage into canonical rational values.
/// The former REAL columns remain only so existing databases can upgrade without
/// rebuilding their BOM tables; runtime code reads and writes the exact columns.
public struct MigrationV022: Migration {
    public let version: SchemaVersion = .v22
    public let description = "Store BOM quantities as exact rational values and enforce unique components"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try addColumnIfMissing(
            "output_quantity_numerator",
            definition: "INTEGER NOT NULL DEFAULT 1 CHECK(output_quantity_numerator > 0)",
            to: "avelo_boms",
            db: db
        )
        try addColumnIfMissing(
            "output_quantity_denominator",
            definition: "INTEGER NOT NULL DEFAULT 1 CHECK(output_quantity_denominator > 0)",
            to: "avelo_boms",
            db: db
        )
        try addColumnIfMissing(
            "quantity_numerator",
            definition: "INTEGER NOT NULL DEFAULT 1 CHECK(quantity_numerator > 0)",
            to: "avelo_bom_components",
            db: db
        )
        try addColumnIfMissing(
            "quantity_denominator",
            definition: "INTEGER NOT NULL DEFAULT 1 CHECK(quantity_denominator > 0)",
            to: "avelo_bom_components",
            db: db
        )

        try backfillBOMOutputQuantities(in: db)
        try backfillComponentQuantities(in: db)
        try coalesceLegacyDuplicateComponents(in: db)
        try db.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_avelo_bom_components_unique_item ON avelo_bom_components(bom_id, component_item_id);"
        )
    }

    private func addColumnIfMissing(_ column: String,
                                    definition: String,
                                    to table: String,
                                    db: SQLiteDatabase) throws {
        let columns: [String] = try db.query("PRAGMA table_info(\(table))") { try $0.requiredText("name") }
        guard !columns.contains(column) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func backfillBOMOutputQuantities(in db: SQLiteDatabase) throws {
        let rows: [(id: String, legacyQuantity: String)] = try db.query(
            "SELECT id, output_quantity AS legacy_quantity FROM avelo_boms"
        ) { row in
            (try row.requiredText("id"), try row.requiredText("legacy_quantity"))
        }
        for row in rows {
            let quantity = try exactQuantity(
                fromLegacyDecimal: row.legacyQuantity,
                table: "avelo_boms",
                id: row.id,
                column: "output_quantity"
            )
            try db.execute(
                """
                UPDATE avelo_boms
                   SET output_quantity_numerator = ?, output_quantity_denominator = ?
                 WHERE id = ?
                """,
                [.integer(quantity.numerator), .integer(quantity.denominator), .text(row.id)]
            )
        }
    }

    private func backfillComponentQuantities(in db: SQLiteDatabase) throws {
        let rows: [(id: String, legacyQuantity: String)] = try db.query(
            "SELECT id, quantity AS legacy_quantity FROM avelo_bom_components"
        ) { row in
            (try row.requiredText("id"), try row.requiredText("legacy_quantity"))
        }
        for row in rows {
            let quantity = try exactQuantity(
                fromLegacyDecimal: row.legacyQuantity,
                table: "avelo_bom_components",
                id: row.id,
                column: "quantity"
            )
            try db.execute(
                """
                UPDATE avelo_bom_components
                   SET quantity_numerator = ?, quantity_denominator = ?
                 WHERE id = ?
                """,
                [.integer(quantity.numerator), .integer(quantity.denominator), .text(row.id)]
            )
        }
    }

    private func coalesceLegacyDuplicateComponents(in db: SQLiteDatabase) throws {
        let groups: [(bomId: String, componentItemId: String)] = try db.query(
            """
            SELECT bom_id, component_item_id
            FROM avelo_bom_components
            GROUP BY bom_id, component_item_id
            HAVING COUNT(*) > 1
            """
        ) { row in
            (try row.requiredText("bom_id"), try row.requiredText("component_item_id"))
        }

        for group in groups {
            let components: [(id: String, quantity: ExactQuantity)] = try db.query(
                """
                SELECT id, quantity_numerator, quantity_denominator
                FROM avelo_bom_components
                WHERE bom_id = ? AND component_item_id = ?
                ORDER BY line_order ASC, id ASC
                """,
                bind: [.text(group.bomId), .text(group.componentItemId)]
            ) { row in
                (
                    try row.requiredText("id"),
                    try ExactQuantity(
                        numerator: row.requiredInt("quantity_numerator"),
                        denominator: row.requiredInt("quantity_denominator")
                    )
                )
            }
            guard let retained = components.first else { continue }

            let combined = try components.dropFirst().reduce(retained.quantity) { partial, component in
                try ExactQuantity.add(
                    partial,
                    component.quantity,
                    context: "merging duplicate BOM components during migration"
                )
            }
            try db.execute(
                """
                UPDATE avelo_bom_components
                   SET quantity_numerator = ?, quantity_denominator = ?
                 WHERE id = ?
                """,
                [.integer(combined.numerator), .integer(combined.denominator), .text(retained.id)]
            )
            try db.execute(
                """
                DELETE FROM avelo_bom_components
                WHERE bom_id = ? AND component_item_id = ? AND id != ?
                """,
                [.text(group.bomId), .text(group.componentItemId), .text(retained.id)]
            )
        }
    }

    private func exactQuantity(fromLegacyDecimal raw: String,
                               table: String,
                               id: String,
                               column: String) throws -> ExactQuantity {
        do {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = text.split(
                maxSplits: 1,
                omittingEmptySubsequences: false,
                whereSeparator: { $0 == "e" || $0 == "E" }
            )
            guard parts.count <= 2, !parts[0].isEmpty else {
                throw AppError.businessRule("invalid decimal representation \"\(raw)\"")
            }

            let mantissa = try ExactQuantity.parse(decimal: String(parts[0]))
            guard !mantissa.isZero else {
                throw AppError.businessRule("quantity must be greater than zero")
            }
            guard parts.count == 2 else { return mantissa }

            guard let exponent = Int(parts[1]), (-18...18).contains(exponent) else {
                throw AppError.businessRule("exponent is outside the exact storage range")
            }
            let scale = try tenToPower(abs(exponent))
            if exponent > 0 {
                return try ExactQuantity(
                    numerator: CheckedMath.multiply(mantissa.numerator, scale, context: "migrating BOM quantity"),
                    denominator: mantissa.denominator
                )
            }
            if exponent < 0 {
                return try ExactQuantity(
                    numerator: mantissa.numerator,
                    denominator: CheckedMath.multiply(mantissa.denominator, scale, context: "migrating BOM quantity")
                )
            }
            return mantissa
        } catch {
            throw AppError.database(.migrationFailed(
                "Cannot convert \(table).\(column) for row \(id) from \"\(raw)\" to an exact quantity: \(AppError.wrap(error).localizedMessage)"
            ))
        }
    }

    private func tenToPower(_ exponent: Int) throws -> Int64 {
        var result: Int64 = 1
        for _ in 0..<exponent {
            result = try CheckedMath.multiply(result, 10, context: "migrating BOM decimal scale")
        }
        return result
    }
}
