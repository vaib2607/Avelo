import XCTest
@testable import Avelo

/// AVL-P1-040 (Sales/Purchase Orders UI): the order backend previously had
/// zero test coverage. These tests cover creation validation, listing,
/// fulfilment recording, status transitions, and cross-company isolation.
final class InventoryOrderServiceTests: XCTestCase {

    private func makeItem(_ tc: TestCompany, code: String = "ITEM-1") throws -> InventoryItem.ID {
        try InventoryService(db: tc.db, companyId: tc.companyId).createItem(code: code, name: "Widget", unit: "Nos").id
    }

    func testCreateOrderPersistsOrderAndLines() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        let order = try svc.createOrder(
            type: .purchaseOrder,
            number: "PO-1",
            partyAccountId: tc.cashId,
            orderDate: DateFormatters.parseDate("2024-06-01")!,
            expectedDate: DateFormatters.parseDate("2024-06-15"),
            lines: [.init(itemId: itemId, quantity: 10, unitRatePaise: 50_000)]
        )

        XCTAssertEqual(order.status, .open)
        let lines = try svc.linesForOrder(order.id)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].quantity, 10)
        XCTAssertEqual(lines[0].fulfilledQuantity, 0)
    }

    func testCreateOrderRejectsEmptyNumber() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.createOrder(
            type: .salesOrder, number: "  ", partyAccountId: tc.cashId,
            orderDate: Date(), expectedDate: nil,
            lines: [.init(itemId: itemId, quantity: 1)]
        ))
    }

    func testCreateOrderRejectsEmptyLines() throws {
        let tc = try TestCompany.make()
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.createOrder(
            type: .salesOrder, number: "SO-1", partyAccountId: tc.cashId,
            orderDate: Date(), expectedDate: nil, lines: []
        ))
    }

    func testCreateOrderRejectsZeroQuantityLine() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.createOrder(
            type: .salesOrder, number: "SO-1", partyAccountId: tc.cashId,
            orderDate: Date(), expectedDate: nil,
            lines: [.init(itemId: itemId, quantity: 0)]
        ))
    }

    func testCreateOrderRejectsForeignCompanyItem() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.make()
        let foreignItemId = try makeItem(other)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.createOrder(
            type: .salesOrder, number: "SO-1", partyAccountId: tc.cashId,
            orderDate: Date(), expectedDate: nil,
            lines: [.init(itemId: foreignItemId, quantity: 1)]
        ))
    }

    func testOrdersFiltersByTypeAndStatus() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let po = try svc.createOrder(type: .purchaseOrder, number: "PO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 1)])
        _ = try svc.createOrder(type: .salesOrder, number: "SO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 1)])
        try svc.closeOrder(po.id)

        XCTAssertEqual(try svc.orders(type: .purchaseOrder).count, 1)
        XCTAssertEqual(try svc.orders(type: .salesOrder).count, 1)
        XCTAssertEqual(try svc.orders(status: .open).count, 1)
        XCTAssertEqual(try svc.orders(status: .closed).count, 1)
        XCTAssertEqual(try svc.orders().count, 2)
    }

    func testRecordFulfillmentUpdatesLineAndPendingLines() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let order = try svc.createOrder(type: .purchaseOrder, number: "PO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 10)])
        let lineId = try svc.linesForOrder(order.id)[0].id

        try svc.recordFulfillment(orderLineId: lineId, fulfilledQuantity: 4)

        let updated = try svc.linesForOrder(order.id)[0]
        XCTAssertEqual(updated.fulfilledQuantity, 4)
        XCTAssertEqual(updated.pendingQuantity, 6)
        let pending = try svc.pendingLines(type: .purchaseOrder)
        XCTAssertEqual(pending.first?.pendingQuantity, 6)
    }

    func testRecordFulfillmentRejectsQuantityAboveOrdered() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let order = try svc.createOrder(type: .purchaseOrder, number: "PO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 5)])
        let lineId = try svc.linesForOrder(order.id)[0].id

        XCTAssertThrowsError(try svc.recordFulfillment(orderLineId: lineId, fulfilledQuantity: 6))
    }

    func testRecordFulfillmentRejectsOnClosedOrder() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let order = try svc.createOrder(type: .purchaseOrder, number: "PO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 5)])
        let lineId = try svc.linesForOrder(order.id)[0].id
        try svc.closeOrder(order.id)

        XCTAssertThrowsError(try svc.recordFulfillment(orderLineId: lineId, fulfilledQuantity: 1))
    }

    func testCloseThenCloseAgainFails() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let order = try svc.createOrder(type: .purchaseOrder, number: "PO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 5)])

        try svc.closeOrder(order.id)
        XCTAssertThrowsError(try svc.closeOrder(order.id))
    }

    func testCancelOrderSetsCancelledStatus() throws {
        let tc = try TestCompany.make()
        let itemId = try makeItem(tc)
        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        let order = try svc.createOrder(type: .salesOrder, number: "SO-1", partyAccountId: tc.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 5)])

        try svc.cancelOrder(order.id)

        XCTAssertEqual(try svc.orders(status: .cancelled).first?.id, order.id)
    }

    func testLinesForOrderRejectsForeignCompanyOrder() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.make()
        let itemId = try makeItem(other)
        let otherSvc = InventoryOrderService(db: other.db, companyId: other.companyId)
        let order = try otherSvc.createOrder(type: .salesOrder, number: "SO-1", partyAccountId: other.cashId, orderDate: Date(), expectedDate: nil, lines: [.init(itemId: itemId, quantity: 1)])

        let svc = InventoryOrderService(db: tc.db, companyId: tc.companyId)
        XCTAssertThrowsError(try svc.linesForOrder(order.id))
    }
}
