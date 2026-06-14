import XCTest
@testable import Avelo

final class InventoryServiceTests: XCTestCase {

    private func makeItem(_ tc: TestCompany) throws -> InventoryItem {
        try InventoryService(db: tc.db, companyId: tc.companyId)
            .createItem(code: "ITEM001", name: "Rice", unit: "KG",
                        openingQuantity: 0, openingRatePaise: 0)
    }

    func testInventoryMasterFieldsRoundTrip() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId)
            .createItem(code: "ITEM002", name: "Wheat", unit: "KG",
                        openingQuantity: 1, openingRatePaise: 2500,
                        stockGroup: "Grains", stockCategory: "Staples", godown: "Main",
                        hsnSac: "1001")
        let loaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(loaded.stockGroup, "Grains")
        XCTAssertEqual(loaded.stockCategory, "Staples")
        XCTAssertEqual(loaded.godown, "Main")
        XCTAssertEqual(loaded.hsnSac, "1001")
    }

    func testInventoryDisabledCompanyRejectsPublicOperations() throws {
        let tc = try TestCompany.make()
        try tc.db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 0 WHERE id = ?",
            [.text(tc.companyId.uuidString)]
        )
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.listItems()) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("inventory is disabled"))
        }
        XCTAssertThrowsError(
            try svc.createItem(code: "DISABLED", name: "Disabled", unit: "NOS", openingQuantity: 0, openingRatePaise: 0)
        ) { error in
            guard case AppError.featureUnavailable = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
        }
    }

    func testBatchTrackingFieldsRoundTrip() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)
        let mfg = DateFormatters.parseDate("2024-01-10")!
        let exp = DateFormatters.parseDate("2025-01-10")!

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 10, ratePaise: 1250,
                               batchNumber: "B-1001", manufactureDate: mfg, expiryDate: exp)

        let movement = try XCTUnwrap(InventoryRepository(db: tc.db)
            .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id)).first)
        XCTAssertEqual(movement.batchNumber, "B-1001")
        XCTAssertEqual(movement.manufactureDate?.timeIntervalSince1970 ?? 0, mfg.timeIntervalSince1970, accuracy: 0.1)
        XCTAssertEqual(movement.expiryDate?.timeIntervalSince1970 ?? 0, exp.timeIntervalSince1970, accuracy: 0.1)
    }

    // MARK: - Fractional quantity

    func testFractionalQuantityRoundTrips() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 2.75, ratePaise: 10000)

        let bal = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id,
                                                                    asOf: DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(bal.onHandQty, 2.75, accuracy: 0.001)
    }

    func testFractionalQuantityIsNotTruncatedToInteger() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        // The old bug truncated 0.75 → 0, recording a zero-quantity movement
        // (which the validator would now reject). A successful insert with the
        // correct on-hand proves no truncation occurred.
        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 0.75, ratePaise: 10000)

        let bal = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id,
                                                                    asOf: DateFormatters.parseDate("2024-06-01")!)
        XCTAssertGreaterThan(bal.onHandQty, 0.5)
    }

    func testTotalValuePaiseIsRoundedNotTruncated() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        // 1.5 kg × ₹33.33/kg = ₹49.995 → should round to ₹50.00 (5000 paise)
        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 1.5, ratePaise: 3333)

        let movements = try InventoryRepository(db: tc.db)
            .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id))
        XCTAssertEqual(movements.first?.totalValuePaise, 5000) // 1.5 × 3333 = 4999.5 → rounds to 5000 paise
    }

    // MARK: - Zero-quantity rejection

    func testZeroQuantityThrows() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                                   type: .purchase, quantity: 0, ratePaise: 10000)
        ) { error in
            guard case AppError.validation(let ve) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(ve.code, .stockMovementQuantityZero)
        }
    }

    func testZeroValuedMovementSucceedsForFreeSample() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        XCTAssertNoThrow(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                                   type: .purchase, quantity: 1, ratePaise: 0, notes: "Free sample")
        )
        let movements = try InventoryRepository(db: tc.db)
            .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id))
        XCTAssertEqual(movements.first?.totalValuePaise, 0)
    }

    // MARK: - Stock availability guard (E2 — was dead before)

    func testOutMovementBeyondStockThrows() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        // Record 5 kg in.
        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 5, ratePaise: 10000)

        // Try to sell 6 kg — must throw quantityExceedsStock.
        XCTAssertThrowsError(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!,
                                   type: .sale, quantity: 6, ratePaise: 10000)
        ) { error in
            guard case AppError.validation(let ve) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(ve.code, .quantityExceedsStock)
        }
    }

    func testOutMovementWithinStockSucceeds() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .purchase, quantity: 5, ratePaise: 10000)
        XCTAssertNoThrow(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!,
                                   type: .sale, quantity: 3.5, ratePaise: 10000)
        )
        let bal = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id,
                                                                    asOf: DateFormatters.parseDate("2024-06-15")!)
        XCTAssertEqual(bal.onHandQty, 1.5, accuracy: 0.001)
    }

    // MARK: - Validator purity tests (no DB)

    func testValidatorAcceptsValidInput() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .purchase,
            quantity: 2.5, unitCostPaise: 10000, totalValuePaise: 25000, currentOnHandQty: 0
        ))
        XCTAssertTrue(v.isValid)
    }

    func testValidatorRejectsNegativeCost() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .purchase,
            quantity: 1.0, unitCostPaise: -100, totalValuePaise: -100, currentOnHandQty: 0
        ))
        XCTAssertFalse(v.isValid)
        XCTAssertEqual(v.errors.first?.code, .stockMovementCostMismatch)
    }

    func testValidatorRejectsExceedingStockForAllOutTypes() {
        let outTypes: [MovementType] = [.stockOut, .sale, .purchaseReturn, .adjustmentOut]
        for type in outTypes {
            let v = StockMovementValidator().validate(.init(
                itemId: UUID(), date: Date(), movementType: type,
                quantity: 10.0, unitCostPaise: 1000, totalValuePaise: 10000, currentOnHandQty: 5.0
            ))
            XCTAssertFalse(v.isValid, "\(type.rawValue) should fail when qty > onHand")
            XCTAssertTrue(v.errors.contains(where: { $0.code == .quantityExceedsStock }),
                          "\(type.rawValue) missing quantityExceedsStock error")
        }
    }
}
