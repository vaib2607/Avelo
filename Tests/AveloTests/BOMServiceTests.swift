import XCTest
@testable import Avelo

private struct BOMAuditPayload: Decodable {
    let bom: BillOfMaterials
    let components: [BOMComponent]
}

final class BOMServiceTests: XCTestCase {
    private func quantity(_ decimal: String) throws -> ExactQuantity {
        try ExactQuantity.parse(decimal: decimal)
    }

    private func component(companyId: Company.ID,
                           itemId: InventoryItem.ID,
                           quantity decimal: String) throws -> BOMComponent {
        BOMComponent(
            companyId: companyId,
            bomId: UUID(),
            componentItemId: itemId,
            quantity: try quantity(decimal)
        )
    }

    func testCreateAndLoadBOMRoundTripsExactQuantitiesWithoutDrift() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let output = try quantity("0.1")
        let componentAQuantity = try quantity("0.2")
        let componentBQuantity = try quantity("1.125")

        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let componentA = try inventory.createItem(code: "RM-001", name: "Raw A", unit: "PCS")
        let componentB = try inventory.createItem(code: "RM-002", name: "Raw B", unit: "PCS")

        try bomService.createBOM(
            assemblyItemId: assembly.id,
            outputQuantity: output,
            components: [
                try component(companyId: tc.companyId, itemId: componentA.id, quantity: "0.2"),
                try component(companyId: tc.companyId, itemId: componentB.id, quantity: "1.125")
            ]
        )

        let loaded = try XCTUnwrap(bomService.loadBOM(for: assembly.id))
        XCTAssertEqual(loaded.0.assemblyItemId, assembly.id)
        XCTAssertEqual(loaded.0.outputQuantity, output)
        XCTAssertEqual(loaded.0.outputQuantity.numerator, 1)
        XCTAssertEqual(loaded.0.outputQuantity.denominator, 10)
        XCTAssertEqual(BOMQuantityFormat.display(try quantity("0.125")), "0.125")
        XCTAssertEqual(loaded.1.count, 2)
        XCTAssertEqual(loaded.1[0].componentItemId, componentA.id)
        XCTAssertEqual(loaded.1[0].quantity, componentAQuantity)
        XCTAssertEqual(loaded.1[0].lineOrder, 0)
        XCTAssertEqual(loaded.1[1].componentItemId, componentB.id)
        XCTAssertEqual(loaded.1[1].quantity, componentBQuantity)
        XCTAssertEqual(loaded.1[1].lineOrder, 1)
    }

    func testListBOMsReturnsAssemblyNameAndComponentCount() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let output = try quantity("5")
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let componentA = try inventory.createItem(code: "RM-001", name: "Raw A", unit: "PCS")

        try bomService.createBOM(
            assemblyItemId: assembly.id,
            outputQuantity: output,
            components: [try component(companyId: tc.companyId, itemId: componentA.id, quantity: "2")]
        )

        let rows = try bomService.listBOMs()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].assemblyItemName, "Finished Good")
        XCTAssertEqual(rows[0].componentCount, 1)
        XCTAssertEqual(rows[0].bom.outputQuantity, output)
        XCTAssertTrue(rows[0].isEditable)
    }

    func testCreateRejectsDuplicateComponentsWithoutWritingBOM() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let raw = try inventory.createItem(code: "RM-001", name: "Raw", unit: "PCS")

        XCTAssertThrowsError(
            try bomService.createBOM(
                assemblyItemId: assembly.id,
                outputQuantity: try quantity("1"),
                components: [
                    try component(companyId: tc.companyId, itemId: raw.id, quantity: "1"),
                    try component(companyId: tc.companyId, itemId: raw.id, quantity: "2")
                ]
            )
        ) { error in
            guard case AppError.validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertTrue(validation.message.localizedCaseInsensitiveContains("only appear once"))
        }

        XCTAssertNil(try bomService.loadBOM(for: assembly.id))
    }

    func testCreateRefusesExistingAssemblyWhileExplicitUpdateReplacesRecipe() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let output = try quantity("1")
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let rawA = try inventory.createItem(code: "RM-001", name: "Raw A", unit: "PCS")
        let rawB = try inventory.createItem(code: "RM-002", name: "Raw B", unit: "PCS")

        try bomService.createBOM(
            assemblyItemId: assembly.id,
            outputQuantity: output,
            components: [try component(companyId: tc.companyId, itemId: rawA.id, quantity: "2")]
        )
        let original = try XCTUnwrap(bomService.loadBOM(for: assembly.id))

        XCTAssertThrowsError(
            try bomService.createBOM(
                assemblyItemId: assembly.id,
                outputQuantity: output,
                components: [try component(companyId: tc.companyId, itemId: rawB.id, quantity: "3")]
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("edit flow"))
        }

        let afterRejectedCreate = try XCTUnwrap(bomService.loadBOM(for: assembly.id))
        XCTAssertEqual(afterRejectedCreate.0.id, original.0.id)
        XCTAssertEqual(afterRejectedCreate.1.map(\.componentItemId), [rawA.id])

        try bomService.updateBOM(
            assemblyItemId: assembly.id,
            outputQuantity: try quantity("2.5"),
            components: [try component(companyId: tc.companyId, itemId: rawB.id, quantity: "3")]
        )

        let updated = try XCTUnwrap(bomService.loadBOM(for: assembly.id))
        XCTAssertEqual(updated.0.id, original.0.id)
        XCTAssertEqual(updated.0.outputQuantity, try quantity("2.5"))
        XCTAssertEqual(updated.1.map(\.componentItemId), [rawB.id])
    }

    func testCreateAndUpdateRecordDurableBeforeAndAfterAuditSnapshots() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")
        let rawA = try inventory.createItem(code: "RM-001", name: "Raw A", unit: "PCS")
        let rawB = try inventory.createItem(code: "RM-002", name: "Raw B", unit: "PCS")

        try bomService.createBOM(
            assemblyItemId: assembly.id,
            outputQuantity: try quantity("1"),
            components: [try component(companyId: tc.companyId, itemId: rawA.id, quantity: "2")]
        )
        try bomService.updateBOM(
            assemblyItemId: assembly.id,
            outputQuantity: try quantity("3"),
            components: [try component(companyId: tc.companyId, itemId: rawB.id, quantity: "4")]
        )

        let events = try AuditService(db: tc.db, companyId: tc.companyId).list(
            filter: .init(companyId: tc.companyId, entityType: "bill_of_materials")
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.action)), [.billOfMaterialsCreated, .billOfMaterialsUpdated])

        let created = try XCTUnwrap(events.first(where: { $0.snapshotBeforeJson == nil }))
        let updated = try XCTUnwrap(events.first(where: { $0.snapshotBeforeJson != nil }))
        XCTAssertEqual(created.reason, "Bill of materials recipe setup created.")
        XCTAssertEqual(updated.reason, "Bill of materials recipe setup updated.")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let createdAfter = try decoder.decode(
            BOMAuditPayload.self,
            from: Data(try XCTUnwrap(created.snapshotAfterJson).utf8)
        )
        let updateBefore = try decoder.decode(
            BOMAuditPayload.self,
            from: Data(try XCTUnwrap(updated.snapshotBeforeJson).utf8)
        )
        let updateAfter = try decoder.decode(
            BOMAuditPayload.self,
            from: Data(try XCTUnwrap(updated.snapshotAfterJson).utf8)
        )
        XCTAssertEqual(createdAfter.bom.id, updateBefore.bom.id)
        XCTAssertEqual(updateBefore.components.map(\.componentItemId), [rawA.id])
        XCTAssertEqual(updateAfter.components.map(\.componentItemId), [rawB.id])
        XCTAssertEqual(updateAfter.bom.outputQuantity, try quantity("3"))
        try AuditService(db: tc.db, companyId: tc.companyId).verifyIntegrity()
    }

    func testCreateRejectsDirectCycle() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let assembly = try inventory.createItem(code: "FG-001", name: "Finished Good", unit: "PCS")

        XCTAssertThrowsError(
            try bomService.createBOM(
                assemblyItemId: assembly.id,
                outputQuantity: try quantity("1"),
                components: [try component(companyId: tc.companyId, itemId: assembly.id, quantity: "1")]
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("circular bom"))
        }
    }

    func testUpdateRejectsIndirectCycleAndLeavesExistingRecipeIntact() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let bomService = BOMService(db: tc.db, companyId: tc.companyId)
        let itemA = try inventory.createItem(code: "ASM-A", name: "Assembly A", unit: "PCS")
        let itemB = try inventory.createItem(code: "ASM-B", name: "Assembly B", unit: "PCS")
        let itemC = try inventory.createItem(code: "ASM-C", name: "Assembly C", unit: "PCS")
        let raw = try inventory.createItem(code: "RM-001", name: "Raw", unit: "PCS")

        try bomService.createBOM(
            assemblyItemId: itemB.id,
            outputQuantity: try quantity("1"),
            components: [
                try component(companyId: tc.companyId, itemId: itemC.id, quantity: "1"),
                try component(companyId: tc.companyId, itemId: raw.id, quantity: "2")
            ]
        )
        try bomService.createBOM(
            assemblyItemId: itemC.id,
            outputQuantity: try quantity("1"),
            components: [try component(companyId: tc.companyId, itemId: raw.id, quantity: "1")]
        )
        try bomService.createBOM(
            assemblyItemId: itemA.id,
            outputQuantity: try quantity("1"),
            components: [try component(companyId: tc.companyId, itemId: itemB.id, quantity: "1")]
        )

        XCTAssertThrowsError(
            try bomService.updateBOM(
                assemblyItemId: itemC.id,
                outputQuantity: try quantity("1"),
                components: [try component(companyId: tc.companyId, itemId: itemA.id, quantity: "1")]
            )
        ) { error in
            guard case AppError.businessRule(let message) = AppError.wrap(error) else {
                return XCTFail("Expected business rule error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("circular bom"))
        }

        let unchanged = try XCTUnwrap(bomService.loadBOM(for: itemC.id))
        XCTAssertEqual(unchanged.1.map(\.componentItemId), [raw.id])
    }

    func testListAndValidationAreScopedToActiveCompany() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let inventoryA = InventoryService(db: db, companyId: companyA.companyId)
        let inventoryB = InventoryService(db: db, companyId: companyB.companyId)
        let assemblyA = try inventoryA.createItem(code: "FG-A", name: "A Finished Good", unit: "PCS")
        let assemblyB = try inventoryB.createItem(code: "FG-B", name: "B Finished Good", unit: "PCS")
        let rawB = try inventoryB.createItem(code: "RM-B", name: "B Raw", unit: "PCS")
        let serviceA = BOMService(db: db, companyId: companyA.companyId)
        let serviceB = BOMService(db: db, companyId: companyB.companyId)

        try serviceB.createBOM(
            assemblyItemId: assemblyB.id,
            outputQuantity: try quantity("1"),
            components: [try component(companyId: companyB.companyId, itemId: rawB.id, quantity: "1")]
        )

        XCTAssertTrue(try serviceA.listBOMs().isEmpty)
        XCTAssertThrowsError(
            try serviceA.createBOM(
                assemblyItemId: assemblyA.id,
                outputQuantity: try quantity("1"),
                components: [try component(companyId: companyA.companyId, itemId: rawB.id, quantity: "1")]
            )
        ) { error in
            guard case AppError.validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.field, "componentItemId")
        }
    }

    func testMigrationV022BackfillsExactQuantitiesAndCoalescesLegacyDuplicates() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }
        let bomId = UUID()
        let companyId = UUID()
        let assemblyId = UUID()
        let componentItemId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())

        try db.execute(
            """
            CREATE TABLE avelo_boms (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL,
                assembly_item_id TEXT NOT NULL UNIQUE,
                output_quantity REAL NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try db.execute(
            """
            CREATE TABLE avelo_bom_components (
                id TEXT PRIMARY KEY,
                company_id TEXT NOT NULL,
                bom_id TEXT NOT NULL,
                component_item_id TEXT NOT NULL,
                quantity REAL NOT NULL,
                line_order INTEGER NOT NULL
            )
            """
        )
        try db.execute(
            """
            INSERT INTO avelo_boms
            (id, company_id, assembly_item_id, output_quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [.text(bomId.uuidString), .text(companyId.uuidString), .text(assemblyId.uuidString), .real(0.125), .text(now), .text(now)]
        )
        for (quantity, lineOrder) in [(0.1, 0), (0.2, 1)] {
            try db.execute(
                """
                INSERT INTO avelo_bom_components
                (id, company_id, bom_id, component_item_id, quantity, line_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(companyId.uuidString),
                    .text(bomId.uuidString),
                    .text(componentItemId.uuidString),
                    .real(quantity),
                    .integer(Int64(lineOrder))
                ]
            )
        }

        try MigrationV022().up(db)

        let output = try XCTUnwrap(try db.queryOne(
            "SELECT output_quantity_numerator, output_quantity_denominator FROM avelo_boms WHERE id = ?",
            bind: [.text(bomId.uuidString)]
        ) { row in
            try ExactQuantity(
                numerator: row.requiredInt("output_quantity_numerator"),
                denominator: row.requiredInt("output_quantity_denominator")
            )
        })
        XCTAssertEqual(output, try quantity("0.125"))

        let components: [(quantity: ExactQuantity, count: Int64)] = try db.query(
            """
            SELECT quantity_numerator, quantity_denominator, COUNT(*) AS component_count
            FROM avelo_bom_components
            WHERE bom_id = ? AND component_item_id = ?
            GROUP BY quantity_numerator, quantity_denominator
            """,
            bind: [.text(bomId.uuidString), .text(componentItemId.uuidString)]
        ) { row in
            (
                try ExactQuantity(
                    numerator: row.requiredInt("quantity_numerator"),
                    denominator: row.requiredInt("quantity_denominator")
                ),
                try row.requiredInt("component_count")
            )
        }
        XCTAssertEqual(components.count, 1)
        XCTAssertEqual(components[0].quantity, try quantity("0.3"))
        XCTAssertEqual(components[0].count, 1)

        XCTAssertThrowsError(
            try db.execute(
                """
                INSERT INTO avelo_bom_components
                (id, company_id, bom_id, component_item_id, quantity, line_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(companyId.uuidString),
                    .text(bomId.uuidString),
                    .text(componentItemId.uuidString),
                    .real(1),
                    .integer(2)
                ]
            )
        )
    }
}
