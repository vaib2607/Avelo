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

    func testInventoryMasterRoundTripsAlternateUnitDefinitionExactly() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(
            code: "ITEMALT",
            name: "Tea Pack",
            unit: "KG",
            alternateUnit: "BAG",
            baseUnitsPerAlternateUnit: try ExactQuantity.parse(decimal: "2.5"),
            valuationMethod: .fifo
        )

        let loaded = try XCTUnwrap(InventoryRepository(db: tc.db).findItemById(item.id))
        XCTAssertEqual(loaded.alternateUnit, "BAG")
        XCTAssertEqual(loaded.baseUnitsPerAlternateUnit?.numerator, 5)
        XCTAssertEqual(loaded.baseUnitsPerAlternateUnit?.denominator, 2)
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

    func testAlternateUnitMovementConvertsToAuthoritativeBaseQuantityExactly() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(
            code: "BOX001",
            name: "Bolts",
            unit: "NOS",
            alternateUnit: "BOX",
            baseUnitsPerAlternateUnit: try ExactQuantity.parse(decimal: "12")
        )

        try service.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            type: .stockIn,
            quantity: try ExactQuantity.parse(decimal: "1.5"),
            ratePaise: 100,
            enteredUnit: "BOX"
        )

        let movement = try XCTUnwrap(
            InventoryRepository(db: tc.db)
                .listMovements(filter: .init(companyId: tc.companyId, itemId: item.id))
                .first
        )
        XCTAssertEqual(movement.enteredUnit, "BOX")
        XCTAssertEqual(movement.quantity.numerator, 18)
        XCTAssertEqual(movement.quantity.denominator, 1)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 18)
        XCTAssertEqual(balance.onHandQuantity.denominator, 1)
    }

    func testAlternateUnitFractionalConversionPreservesResidualBaseQuantity() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(
            code: "BAG001",
            name: "Tea Dust",
            unit: "KG",
            alternateUnit: "BAG",
            baseUnitsPerAlternateUnit: try ExactQuantity.parse(decimal: "2.5")
        )

        try service.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            type: .stockIn,
            quantity: try ExactQuantity.parse(decimal: "1"),
            ratePaise: 100,
            enteredUnit: "BAG"
        )

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 5)
        XCTAssertEqual(balance.onHandQuantity.denominator, 2)
    }

    func testFifoStockOutUsesOldestLayersInsteadOfCallerRate() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "FIFO001", name: "FIFO Item", unit: "NOS", valuationMethod: .fifo)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 15, ratePaise: 999)

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        XCTAssertEqual(movements.count, 3)
        XCTAssertEqual(movements.last?.totalValuePaise, 2000)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-03")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 5)
        XCTAssertEqual(balance.onHandValuePaise, 1000)
    }

    func testWeightedAverageStockOutUsesAggregateAverageInsteadOfCallerRate() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "WA001", name: "WA Item", unit: "NOS", valuationMethod: .weightedAverage)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 15, ratePaise: 999)

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        XCTAssertEqual(movements.last?.totalValuePaise, 2250)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-03")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 5)
        XCTAssertEqual(balance.onHandValuePaise, 750)
    }

    func testWeightedAveragePreservesResidualPaiseDeterministically() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "WA002", name: "WA Residual", unit: "NOS", valuationMethod: .weightedAverage)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 3, ratePaise: 100)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 2, ratePaise: 101)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 2, ratePaise: 1)

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        XCTAssertEqual(movements.last?.totalValuePaise, 200)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-03")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 3)
        XCTAssertEqual(balance.onHandValuePaise, 302)
    }

    func testBackdatedInsertRecalculatesDownstreamFifoStockOutPersistedValue() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "FIFO-BD", name: "FIFO Backdated", unit: "NOS", valuationMethod: .fifo)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 5, ratePaise: 999)

        let publication = try service.recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-06-01")!,
            type: .stockIn,
            quantity: 10,
            ratePaise: 100
        )

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        XCTAssertEqual(movements.count, 3)
        XCTAssertEqual(movements[2].movementType, .stockOut)
        XCTAssertEqual(movements[2].totalValuePaise, 500)
        XCTAssertEqual(publication.affectedMovementIds, [movements[2].id])

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-03")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 15)
        XCTAssertEqual(balance.onHandValuePaise, 2500)
    }

    func testReverseMovementRepublishesAuthoritativeTotalsAndRestoresStock() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "REV001", name: "Reverse Item", unit: "NOS", valuationMethod: .fifo)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        _ = try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockOut, quantity: 6, ratePaise: 999)
        let original = try XCTUnwrap(
            InventoryRepository(db: tc.db)
                .listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
                .last
        )

        let reversal = try service.reverseMovement(original.id, reason: "undo issue")

        XCTAssertEqual(reversal.originalMovement.id, original.id)
        XCTAssertEqual(reversal.reversalMovement.movementType, .stockIn)
        XCTAssertEqual(reversal.reversalMovement.totalValuePaise, 600)
        XCTAssertEqual(reversal.publication.phase, .published)

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        XCTAssertEqual(movements.count, 3)
        XCTAssertEqual(movements.last?.totalValuePaise, 600)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-02")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 10)
        XCTAssertEqual(balance.onHandValuePaise, 1000)
    }

    func testReplaceMovementReversesOriginalAndRecalculatesDownstreamWeightedAverage() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "REP001", name: "Replace Item", unit: "NOS", valuationMethod: .weightedAverage)

        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        let originalSecondReceiptPublication = try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        XCTAssertEqual(originalSecondReceiptPublication.affectedMovementIds.count, 0)
        try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 10, ratePaise: 999)

        let originalSecondReceipt = try XCTUnwrap(
            InventoryRepository(db: tc.db)
                .listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
                .first(where: { $0.date == DateFormatters.parseDate("2024-06-02")! && $0.movementType == .stockIn })
        )

        let replacement = try service.replaceMovement(
            originalSecondReceipt.id,
            date: DateFormatters.parseDate("2024-06-02")!,
            type: .stockIn,
            quantity: try ExactQuantity.whole(10),
            ratePaise: 300,
            notes: "corrected rate",
            reason: "rate correction"
        )

        XCTAssertEqual(replacement.reversalMovement.movementType, .stockOut)
        XCTAssertEqual(replacement.replacementMovement.movementType, .stockIn)
        XCTAssertTrue(replacement.publication.affectedMovementCount >= 1)

        let movements = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id)
        let downstreamOut = try XCTUnwrap(movements.first(where: { $0.date == DateFormatters.parseDate("2024-06-03")! && $0.movementType == .stockOut }))
        XCTAssertEqual(downstreamOut.totalValuePaise, 2000)

        let balance = try InventoryRepository(db: tc.db).runningBalance(itemId: item.id, asOf: DateFormatters.parseDate("2024-06-03")!)
        XCTAssertEqual(balance.onHandQuantity.numerator, 10)
        XCTAssertEqual(balance.onHandValuePaise, 2000)
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

    func testValidatorRejectsOverflowingQuantityTimesCost() {
        let v = StockMovementValidator().validate(.init(
            itemId: UUID(), date: Date(), movementType: .stockIn,
            quantity: Int64.max, unitCostPaise: 2, totalValuePaise: 0, currentOnHandQty: 0
        ))
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.code == ValidationErrorCode.arithmeticOverflow }))
    }

    func testRecordMovementThrowsOnOverflowingTotalValue() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)

        XCTAssertThrowsError(
            try InventoryService(db: tc.db, companyId: tc.companyId).recordMovement(
                itemId: item.id,
                date: DateFormatters.parseDate("2024-06-01")!,
                type: .stockIn,
                quantity: Int64.max,
                ratePaise: 2
            )
        ) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule overflow, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
        }
    }

    func testPendingPurchaseAndSalesOrderVisibilityUsesSourceOrderLines() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let service = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        let purchase = try service.createOrder(
            type: .purchaseOrder,
            number: "PO-001",
            partyAccountId: tc.capitalId,
            orderDate: DateFormatters.parseDate("2024-07-01")!,
            expectedDate: DateFormatters.parseDate("2024-07-10")!,
            lines: [.init(itemId: item.id, quantity: 10, fulfilledQuantity: 4, unitRatePaise: 1200)]
        )
        _ = try service.createOrder(
            type: .salesOrder,
            number: "SO-001",
            partyAccountId: tc.salesId,
            orderDate: DateFormatters.parseDate("2024-07-02")!,
            expectedDate: DateFormatters.parseDate("2024-07-11")!,
            lines: [.init(itemId: item.id, quantity: 6, fulfilledQuantity: 1, unitRatePaise: 1500)]
        )

        let purchaseLines = try service.pendingLines(type: .purchaseOrder)
        XCTAssertEqual(purchaseLines.count, 1)
        XCTAssertEqual(purchaseLines.first?.orderId, purchase.id)
        XCTAssertEqual(purchaseLines.first?.pendingQuantity, 6)

        let allLines = try service.pendingLines()
        XCTAssertEqual(allLines.map(\.pendingQuantity).reduce(0, +), 11)
    }

    func testPendingQuantityFailsClosedOnOverflowingCorruptOrderLine() {
        let line = InventoryOrderLine(
            companyId: UUID(),
            orderId: UUID(),
            itemId: UUID(),
            quantity: Int64.max,
            fulfilledQuantity: -1,
            unitRatePaise: 0
        )

        XCTAssertEqual(line.pendingQuantity, 0)
    }

    func testReorderAlertsDoNotFireWhenInventoryIsDisabled() throws {
        let tc = try TestCompany.make()
        let item = try makeItem(tc)
        let service = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        try service.setReorderLevel(itemId: item.id, minimumQuantity: 5, reorderQuantity: 20)
        try tc.db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 0 WHERE id = ?",
            [.text(tc.companyId.uuidString)]
        )

        let alerts = try service.reorderAlerts(asOfDate: DateFormatters.parseDate("2024-07-01")!)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testInventoryOrderWritesRejectForeignCompanyItem() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.seed(into: tc.db, companyId: UUID(), companyName: "Other Co")
        let foreignItem = try InventoryService(db: tc.db, companyId: other.companyId)
            .createItem(code: "OTHER", name: "Other Item", unit: "KG")

        XCTAssertThrowsError(
            try InventoryOrderService(db: tc.db, companyId: tc.companyId).createOrder(
                type: .purchaseOrder,
                number: "PO-FOREIGN",
                partyAccountId: tc.capitalId,
                orderDate: DateFormatters.parseDate("2024-07-01")!,
                expectedDate: nil,
                lines: [.init(itemId: foreignItem.id, quantity: 1)]
            )
        ) { error in
            guard case AppError.validation = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
        }
    }

    // AVL-P0-022: invoice PDF rendering needs movements scoped to one voucher.
    func testListMovementsForVoucherReturnsOnlyThatVouchersMovements() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try service.createItem(code: "SKU-V", name: "Voucher Item", unit: "NOS")

        let voucherA = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-15")!,
            partyAccountId: tc.capitalId,
            lines: [.init(accountId: tc.capitalId, amountPaise: 1000, side: .debit), .init(accountId: tc.salesId, amountPaise: 1000, side: .credit)]
        ), in: tc.fy).voucher
        let voucherB = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: VoucherDraft(
            mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-16")!,
            partyAccountId: tc.capitalId,
            lines: [.init(accountId: tc.capitalId, amountPaise: 1000, side: .debit), .init(accountId: tc.salesId, amountPaise: 1000, side: .credit)]
        ), in: tc.fy).voucher

        _ = try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!, type: .stockIn, quantity: 5, ratePaise: 1000, voucherId: voucherA.id)
        _ = try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!, type: .stockIn, quantity: 3, ratePaise: 1000, voucherId: voucherA.id)
        _ = try service.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-16")!, type: .stockIn, quantity: 1, ratePaise: 1000, voucherId: voucherB.id)

        let forA = try InventoryRepository(db: tc.db).listMovements(forVoucher: voucherA.id)
        let forB = try InventoryRepository(db: tc.db).listMovements(forVoucher: voucherB.id)

        XCTAssertEqual(forA.count, 2)
        XCTAssertEqual(forB.count, 1)
        XCTAssertTrue(forA.allSatisfy { $0.voucherId == voucherA.id })
    }
}
