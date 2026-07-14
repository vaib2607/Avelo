import Foundation

public struct InventoryOrderRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func insertOrder(_ order: InventoryOrder, lines: [InventoryOrderLine]) throws {
        try db.write { tx in
            try tx.execute(
                """
                INSERT INTO avelo_inventory_orders
                (id, company_id, order_type, number, party_account_id, order_date, expected_date, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(order.id.uuidString),
                    .text(order.companyId.uuidString),
                    .text(order.orderType.rawValue),
                    .text(order.number),
                    .text(order.partyAccountId.uuidString),
                    .date(order.orderDate),
                    .optionalDate(order.expectedDate),
                    .text(order.status.rawValue),
                    .timestamp(order.createdAt),
                    .timestamp(order.updatedAt)
                ]
            )
            for line in lines {
                try tx.execute(
                    """
                    INSERT INTO avelo_inventory_order_lines
                    (id, company_id, order_id, item_id, quantity, fulfilled_quantity, unit_rate_paise, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(line.id.uuidString),
                        .text(line.companyId.uuidString),
                        .text(line.orderId.uuidString),
                        .text(line.itemId.uuidString),
                        .integer(line.quantity),
                        .integer(line.fulfilledQuantity),
                        .integer(line.unitRatePaise),
                        .timestamp(line.createdAt)
                    ]
                )
            }
        }
    }

    public func listOrders(companyId: Company.ID, orderType: InventoryOrderType? = nil, status: InventoryOrderStatus? = nil) throws -> [InventoryOrder] {
        var sql = """
            SELECT id, company_id, order_type, number, party_account_id, order_date, expected_date, status, created_at, updated_at
            FROM avelo_inventory_orders
            WHERE company_id = ?
        """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        if let orderType {
            sql += " AND order_type = ?"
            bind.append(.text(orderType.rawValue))
        }
        if let status {
            sql += " AND status = ?"
            bind.append(.text(status.rawValue))
        }
        sql += " ORDER BY order_date DESC, number DESC"
        return try db.query(sql, bind: bind, row: Self.rowToOrder)
    }

    public func findOrder(id: InventoryOrder.ID, companyId: Company.ID) throws -> InventoryOrder? {
        try db.queryOne(
            """
            SELECT id, company_id, order_type, number, party_account_id, order_date, expected_date, status, created_at, updated_at
            FROM avelo_inventory_orders
            WHERE id = ? AND company_id = ?
            """,
            bind: [.text(id.uuidString), .text(companyId.uuidString)],
            row: Self.rowToOrder
        )
    }

    public func linesForOrder(_ orderId: InventoryOrder.ID, companyId: Company.ID) throws -> [InventoryOrderLine] {
        try db.query(
            """
            SELECT id, company_id, order_id, item_id, quantity, fulfilled_quantity, unit_rate_paise, created_at
            FROM avelo_inventory_order_lines
            WHERE order_id = ? AND company_id = ?
            ORDER BY created_at ASC
            """,
            bind: [.text(orderId.uuidString), .text(companyId.uuidString)]
        ) { row in
            InventoryOrderLine(
                id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_inventory_order_lines.id"),
                companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_inventory_order_lines.company_id"),
                orderId: try UUIDParsing.required(row.requiredText("order_id"), field: "avelo_inventory_order_lines.order_id"),
                itemId: try UUIDParsing.required(row.requiredText("item_id"), field: "avelo_inventory_order_lines.item_id"),
                quantity: try row.requiredInt("quantity"),
                fulfilledQuantity: try row.requiredInt("fulfilled_quantity"),
                unitRatePaise: try row.requiredInt("unit_rate_paise"),
                createdAt: try row.timestamp("created_at")
            )
        }
    }

    public func findOrderLine(id: InventoryOrderLine.ID, companyId: Company.ID) throws -> InventoryOrderLine? {
        try db.queryOne(
            """
            SELECT id, company_id, order_id, item_id, quantity, fulfilled_quantity, unit_rate_paise, created_at
            FROM avelo_inventory_order_lines
            WHERE id = ? AND company_id = ?
            """,
            bind: [.text(id.uuidString), .text(companyId.uuidString)]
        ) { row in
            InventoryOrderLine(
                id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_inventory_order_lines.id"),
                companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_inventory_order_lines.company_id"),
                orderId: try UUIDParsing.required(row.requiredText("order_id"), field: "avelo_inventory_order_lines.order_id"),
                itemId: try UUIDParsing.required(row.requiredText("item_id"), field: "avelo_inventory_order_lines.item_id"),
                quantity: try row.requiredInt("quantity"),
                fulfilledQuantity: try row.requiredInt("fulfilled_quantity"),
                unitRatePaise: try row.requiredInt("unit_rate_paise"),
                createdAt: try row.timestamp("created_at")
            )
        }
    }

    public func updateLineFulfillment(_ lineId: InventoryOrderLine.ID, companyId: Company.ID, fulfilledQuantity: Int64) throws {
        try db.execute(
            "UPDATE avelo_inventory_order_lines SET fulfilled_quantity = ? WHERE id = ? AND company_id = ?",
            [.integer(fulfilledQuantity), .text(lineId.uuidString), .text(companyId.uuidString)]
        )
    }

    public func updateOrderStatus(_ orderId: InventoryOrder.ID, companyId: Company.ID, status: InventoryOrderStatus) throws {
        try db.execute(
            "UPDATE avelo_inventory_orders SET status = ?, updated_at = ? WHERE id = ? AND company_id = ?",
            [.text(status.rawValue), .timestamp(Date()), .text(orderId.uuidString), .text(companyId.uuidString)]
        )
    }

    private static func rowToOrder(_ row: Row) throws -> InventoryOrder {
        InventoryOrder(
            id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_inventory_orders.id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_inventory_orders.company_id"),
            orderType: try row.enumValue("order_type"),
            number: try row.requiredText("number"),
            partyAccountId: try UUIDParsing.required(row.requiredText("party_account_id"), field: "avelo_inventory_orders.party_account_id"),
            orderDate: row.date("order_date"),
            expectedDate: try row.checkedOptionalDate("expected_date"),
            status: try row.enumValue("status"),
            createdAt: try row.timestamp("created_at"),
            updatedAt: try row.timestamp("updated_at")
        )
    }

    public func pendingLines(companyId: Company.ID, orderType: InventoryOrderType? = nil) throws -> [PendingInventoryOrderLine] {
        var sql = """
            SELECT l.id, o.id AS order_id, o.order_type, o.number, o.expected_date,
                   party.name AS party_name,
                   i.id AS item_id, i.name AS item_name,
                   l.quantity, l.fulfilled_quantity,
                   (l.quantity - l.fulfilled_quantity) AS pending_quantity
            FROM avelo_inventory_order_lines l
            JOIN avelo_inventory_orders o ON o.id = l.order_id AND o.company_id = l.company_id
            JOIN avelo_inventory_items i ON i.id = l.item_id AND i.company_id = l.company_id
            JOIN avelo_accounts party ON party.id = o.party_account_id AND party.company_id = o.company_id
            WHERE l.company_id = ?
              AND o.status = 'open'
              AND i.is_active = 1
              AND l.fulfilled_quantity < l.quantity
        """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        if let orderType {
            sql += " AND o.order_type = ?"
            bind.append(.text(orderType.rawValue))
        }
        sql += " ORDER BY o.expected_date IS NULL, o.expected_date, o.order_date, o.number"
        return try db.query(sql, bind: bind) { row in
            PendingInventoryOrderLine(
                id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_inventory_order_lines.id"),
                orderId: try UUIDParsing.required(row.requiredText("order_id"), field: "avelo_inventory_orders.id"),
                orderType: try row.enumValue("order_type"),
                orderNumber: try row.requiredText("number"),
                partyAccountName: try row.requiredText("party_name"),
                itemId: try UUIDParsing.required(row.requiredText("item_id"), field: "avelo_inventory_items.id"),
                itemName: try row.requiredText("item_name"),
                quantity: try row.requiredInt("quantity"),
                fulfilledQuantity: try row.requiredInt("fulfilled_quantity"),
                pendingQuantity: try row.requiredInt("pending_quantity"),
                expectedDate: try row.checkedOptionalDate("expected_date")
            )
        }
    }

    public func upsertReorderLevel(_ level: InventoryReorderLevel) throws {
        try db.execute(
            """
            INSERT INTO avelo_inventory_reorder_levels
            (id, company_id, item_id, minimum_quantity, reorder_quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(company_id, item_id) DO UPDATE SET
                minimum_quantity = excluded.minimum_quantity,
                reorder_quantity = excluded.reorder_quantity,
                updated_at = excluded.updated_at
            """,
            [
                .text(level.id.uuidString),
                .text(level.companyId.uuidString),
                .text(level.itemId.uuidString),
                .integer(level.minimumQuantity),
                .integer(level.reorderQuantity),
                .timestamp(level.createdAt),
                .timestamp(level.updatedAt)
            ]
        )
    }

    public func reorderAlerts(companyId: Company.ID, asOfDate: Date) throws -> [ReorderAlert] {
        guard try CompanyRepository(db: db).findById(companyId)?.isInventoryEnabled == true else {
            return []
        }
        let sql = """
            SELECT i.id,
                   i.name,
                   r.minimum_quantity,
                   r.reorder_quantity,
                   COALESCE(SUM(CASE
                       WHEN m.movement_type = 'in' THEN m.quantity
                       WHEN m.movement_type = 'out' THEN -m.quantity
                       WHEN m.movement_type = 'adjustment' THEN m.quantity
                       ELSE 0 END), 0) AS on_hand
            FROM avelo_inventory_reorder_levels r
            JOIN avelo_inventory_items i ON i.id = r.item_id AND i.company_id = r.company_id
            LEFT JOIN avelo_stock_movements m ON m.item_id = i.id AND m.company_id = i.company_id AND m.date <= ?
            WHERE r.company_id = ?
              AND i.is_active = 1
            GROUP BY i.id, i.name, r.minimum_quantity, r.reorder_quantity
            HAVING on_hand <= r.minimum_quantity
            ORDER BY i.name COLLATE NOCASE
        """
        return try db.query(sql, bind: [.date(asOfDate), .text(companyId.uuidString)]) { row in
            ReorderAlert(
                id: try UUIDParsing.required(row.text("id"), field: "avelo_inventory_reorder_levels.item_id"),
                itemName: row.text("name"),
                onHandQuantity: row.int("on_hand"),
                minimumQuantity: row.int("minimum_quantity"),
                reorderQuantity: row.int("reorder_quantity")
            )
        }
    }
}
