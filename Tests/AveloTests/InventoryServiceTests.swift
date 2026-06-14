import XCTest
@testable import Avelo

final class InventoryServiceTests: XCTestCase {

    private func makeItem(_ tc: TestCompany) throws -> InventoryItem {
        try InventoryService(db: tc.db, companyId: tc.companyId)
            .createItem(code: "ITEM001", name: "Rice", unit: "KG")
    }

    func testInventoryMasterFieldsRoundTripFrozenSchema() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId)
            .createItem(code: "ITEM002", name: "Wheat", unit: "KG", valuationMethod: .weightedAverage)

        let loaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(loaded.code, "ITEM002")
        XCTAssertEqual(loaded.name, "Wheat")
        XCTAssertEqual(loaded.unit, "KG")
        XCTAssertEqual(loaded.valuationMethod, .weightedAverage)
        XCTAssertTrue(loaded.isActive)
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
            try svc.createItem(code: "DISABLED", name: "Disabled", unit: "NOS")
        ) { error in
            guard case AppError.featureUnavailable = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
        }
    }

    func testInventoryItemAccountLinkingIsDeferredByFrozenSchema() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)

        XCTAssertThrowsError(
            try InventoryService(db: tc.db, companyId: tc.companyId).linkItemToAccount(itemId: item.id, accountId: tc.salesId)
        ) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }
    }

    func testIntegerQuantityRoundTrips() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .stockIn, quantity: 3, ratePaise: 10000)

        let bal = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id,
                                                                    asOf: DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(bal.onHandQty, 3)
    }

    func testTotalValuePaiseUsesIntegerQuantity() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .stockIn, quantity: 2, ratePaise: 3333)

        let movements = try InventoryRepository(db: tc.db)
            .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id))
        XCTAssertEqual(movements.first?.totalValuePaise, 6666)
    }

    func testZeroQuantityThrows() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                                   type: .stockIn, quantity: 0, ratePaise: 10000)
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
                                   type: .stockIn, quantity: 1, ratePaise: 0, notes: "Free sample")
        )
        let movements = try InventoryRepository(db: tc.db)
            .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id))
        XCTAssertEqual(movements.first?.totalValuePaise, 0)
    }

    func testOutMovementBeyondStockThrows() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!,
                               type: .stockIn, quantity: 5, ratePaise: 10000)

        XCTAssertThrowsError(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!,
                                   type: .stockOut, quantity: 6, ratePaise: 10000)
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
                               type: .stockIn, quantity: 5, ratePaise: 10000)
        XCTAssertNoThrow(
            try svc.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!,
                                   type: .stockOut, quantity: 3, ratePaise: 10000)
        )
        let bal = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id,
                                                                    asOf: DateFormatters.parseDate("2024-06-15")!)
        XCTAssertEqual(bal.onHandQty, 2)
    }

    func testValidatorAcceptsValidInput() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .stockIn,
            quantity: 2, unitCostPaise: 10000, totalValuePaise: 20000, currentOnHandQty: 0
        ))
        XCTAssertTrue(v.isValid)
    }

    func testValidatorRejectsNegativeCost() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .stockIn,
            quantity: 1, unitCostPaise: -100, totalValuePaise: -100, currentOnHandQty: 0
        ))
        XCTAssertFalse(v.isValid)
        XCTAssertEqual(v.errors.first?.code, ValidationErrorCode.stockMovementCostMismatch)
    }

    func testValidatorRejectsExceedingStockForOutType() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .stockOut,
            quantity: 10, unitCostPaise: 1000, totalValuePaise: 10000, currentOnHandQty: 5
        ))
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.code == ValidationErrorCode.quantityExceedsStock }))
    }
}
