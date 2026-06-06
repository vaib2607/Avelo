import Foundation

public struct InventoryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findItemById(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT id, company_id, code, name, unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM mally_inventory_items WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToItem($0) }
    }

    public func findItemByCode(_ code: String, companyId: Company.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT id, company_id, code, name, unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM mally_inventory_items WHERE company_id = ? AND code = ?",
            bind: [.text(companyId.uuidString), .text(code)]
        ) { try Self.rowToItem($0) }
    }

    public func listItemsForCompany(_ companyId: Company.ID, includeInactive: Bool = false) throws -> [InventoryItem] {
        let sql = "SELECT id, company_id, code, name, unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM mally_inventory_items WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1") ORDER BY code COLLATE NOCASE"
        return try db.query(sql, bind: [.text(companyId.uuidString)]) { try Self.rowToItem($0) }
    }

    public func listItems(companyId: Company.ID, includeArchived: Bool = false) throws -> [InventoryItem] {
        try listItemsForCompany(companyId, includeInactive: includeArchived)
    }

    public func findItem(id: InventoryItem.ID) throws -> InventoryItem? {
        try findItemById(id)
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try disableItem(id)
    }

    public func setItemAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
        try db.execute(
            "UPDATE mally_inventory_items SET linked_account_id = ? WHERE id = ?",
            [.text(accountId.uuidString), .text(itemId.uuidString)]
        )
    }

    public func insertItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            INSERT INTO mally_inventory_items
            (id, company_id, code, name, unit, valuation_method, is_active,
             opening_quantity, opening_rate_paise, gst_rate, barcode, hsn_sac, is_archived, linked_account_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.companyId.uuidString),
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .real(item.openingQuantity),
                .integer(item.openingRatePaise),
                .real(item.gstRate),
                .optionalText(item.barcode),
                .optionalText(item.hsnSac),
                .bool(item.isArchived),
                .optionalText(item.linkedAccountId?.uuidString),
                .timestamp(item.createdAt)
            ]
        )
    }

    public func updateItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            UPDATE mally_inventory_items SET
                code = ?, name = ?, unit = ?, valuation_method = ?, is_active = ?,
                opening_quantity = ?, opening_rate_paise = ?, gst_rate = ?,
                barcode = ?, hsn_sac = ?, is_archived = ?, linked_account_id = ?
            WHERE id = ?
            """,
            [
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .real(item.openingQuantity),
                .integer(item.openingRatePaise),
                .real(item.gstRate),
                .optionalText(item.barcode),
                .optionalText(item.hsnSac),
                .bool(item.isArchived),
                .optionalText(item.linkedAccountId?.uuidString),
                .text(item.id.uuidString)
            ]
        )
    }

    public func disableItem(_ id: InventoryItem.ID) throws {
        try db.execute(
            "UPDATE mally_inventory_items SET is_active = 0 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    public func insertMovement(_ m: StockMovement) throws {
        try db.execute(
            """
            INSERT INTO mally_stock_movements
            (id, company_id, item_id, voucher_id, date, movement_type, quantity,
             unit_cost_paise, total_value_paise, reference_voucher_number, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(m.id.uuidString),
                .text(m.companyId.uuidString),
                .text(m.itemId.uuidString),
                .optionalText(m.voucherId?.uuidString),
                .date(m.date),
                .text(m.movementType.rawValue),
                .integer(m.quantity),
                .integer(m.unitCostPaise),
                .integer(m.totalValuePaise),
                .optionalText(m.referenceVoucherNumber),
                .optionalText(m.reason),
                .timestamp(m.createdAt)
            ]
        )
    }

    public struct MovementFilter: Sendable {
        public var companyId: Company.ID
        public var itemId: InventoryItem.ID?
        public var fromDate: Date?
        public var toDate: Date?
        public var movementType: MovementType?
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    itemId: InventoryItem.ID? = nil,
                    fromDate: Date? = nil,
                    toDate: Date? = nil,
                    movementType: MovementType? = nil,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.itemId = itemId
            self.fromDate = fromDate
            self.toDate = toDate
            self.movementType = movementType
            self.limit = limit
            self.offset = offset
        }
    }

    public func listMovements(filter: MovementFilter) throws -> [StockMovement] {
        var sql = """
            SELECT id, company_id, item_id, voucher_id, date, movement_type, quantity,
                   unit_cost_paise, total_value_paise, reference_voucher_number, reason, created_at
            FROM mally_stock_movements
            WHERE company_id = ?
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let itemId = filter.itemId {
            sql += " AND item_id = ?"
            bind.append(.text(itemId.uuidString))
        }
        if let from = filter.fromDate {
            sql += " AND date >= ?"
            bind.append(.date(from))
        }
        if let to = filter.toDate {
            sql += " AND date <= ?"
            bind.append(.date(to))
        }
        if let mt = filter.movementType {
            sql += " AND movement_type = ?"
            bind.append(.text(mt.rawValue))
        }
        sql += " ORDER BY date DESC, created_at DESC LIMIT ? OFFSET ?"
        bind.append(.integer(Int64(filter.limit)))
        bind.append(.integer(Int64(filter.offset)))
        return try db.query(sql, bind: bind) { try Self.rowToMovement($0) }
    }

    public struct ItemBalance: Sendable {
        public let itemId: InventoryItem.ID
        public let inQty: Int64
        public let outQty: Int64
        public let adjustmentQty: Int64
        public let inValuePaise: Int64
        public let outValuePaise: Int64
        public let onHandQty: Int64
        public let onHandValuePaise: Int64
    }

    public func runningBalance(itemId: InventoryItem.ID, asOf: Date) throws -> ItemBalance {
        let asOfStr = DateFormatters.formatIsoDate(asOf)
        let row: (Int64, Int64, Int64, Int64, Int64, Int64)? = try db.queryOne(
            """
            SELECT
                COALESCE(SUM(CASE WHEN movement_type = 'in'         THEN quantity ELSE 0 END), 0) AS in_q,
                COALESCE(SUM(CASE WHEN movement_type = 'out'        THEN quantity ELSE 0 END), 0) AS out_q,
                COALESCE(SUM(CASE WHEN movement_type = 'adjustment' THEN quantity ELSE 0 END), 0) AS adj_q,
                COALESCE(SUM(CASE WHEN movement_type = 'in'         THEN total_value_paise ELSE 0 END), 0) AS in_v,
                COALESCE(SUM(CASE WHEN movement_type = 'out'        THEN total_value_paise ELSE 0 END), 0) AS out_v,
                COALESCE(SUM(CASE WHEN movement_type = 'in'         THEN quantity
                                  WHEN movement_type = 'out'        THEN -quantity
                                  WHEN movement_type = 'adjustment' THEN quantity
                                  ELSE 0 END), 0) AS on_hand
            FROM mally_stock_movements
            WHERE item_id = ? AND date <= ?
            """,
            bind: [.text(itemId.uuidString), .text(asOfStr)]
        ) { r in (r.int(0), r.int(1), r.int(2), r.int(3), r.int(4), r.int(5)) }
        let inQty = row?.0 ?? 0
        let outQty = row?.1 ?? 0
        let adjQty = row?.2 ?? 0
        let inVal = row?.3 ?? 0
        let outVal = row?.4 ?? 0
        let onHand = inQty - outQty + adjQty
        let onHandVal = inVal - outVal
        return ItemBalance(
            itemId: itemId,
            inQty: inQty,
            outQty: outQty,
            adjustmentQty: adjQty,
            inValuePaise: inVal,
            outValuePaise: outVal,
            onHandQty: onHand,
            onHandValuePaise: onHandVal
        )
    }

    static func rowToItem(_ r: Row) throws -> InventoryItem {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let vm = ValuationMethod(rawValue: r.text("valuation_method")) ?? .fifo
        return InventoryItem(
            id: id,
            companyId: companyId,
            code: r.text("code"),
            name: r.text("name"),
            unit: r.text("unit"),
            valuationMethod: vm,
            isActive: r.bool("is_active"),
            openingQuantity: r.real("opening_quantity"),
            openingRatePaise: r.int("opening_rate_paise"),
            gstRate: r.real("gst_rate"),
            barcode: r.optionalText("barcode"),
            hsnSac: r.optionalText("hsn_sac"),
            isArchived: r.bool("is_archived"),
            linkedAccountId: r.optionalText("linked_account_id").flatMap { UUID(uuidString: $0) },
            createdAt: r.timestamp("created_at")
        )
    }

    static func rowToMovement(_ r: Row) throws -> StockMovement {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let itemId = UUID(uuidString: r.text("item_id")) ?? UUID()
        let voucherId = r.optionalText("voucher_id").flatMap { UUID(uuidString: $0) }
        let mt = MovementType(rawValue: r.text("movement_type")) ?? .adjustment
        return StockMovement(
            id: id,
            companyId: companyId,
            itemId: itemId,
            date: r.date("date"),
            movementType: mt,
            quantity: r.int("quantity"),
            unitCostPaise: r.int("unit_cost_paise"),
            totalValuePaise: r.int("total_value_paise"),
            voucherId: voucherId,
            referenceVoucherNumber: r.optionalText("reference_voucher_number"),
            reason: r.optionalText("reason"),
            createdAt: r.timestamp("created_at")
        )
    }
}
