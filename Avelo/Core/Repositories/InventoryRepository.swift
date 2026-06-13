import Foundation

public struct InventoryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findItemById(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToItem($0) }
    }

    public func findItemByCode(_ code: String, companyId: Company.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE company_id = ? AND code = ?",
            bind: [.text(companyId.uuidString), .text(code)]
        ) { try Self.rowToItem($0) }
    }

    public func listItemsForCompany(_ companyId: Company.ID, includeInactive: Bool = false) throws -> [InventoryItem] {
        let sql = "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1") ORDER BY code COLLATE NOCASE"
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
            "UPDATE avelo_inventory_items SET linked_account_id = ? WHERE id = ?",
            [.text(accountId.uuidString), .text(itemId.uuidString)]
        )
    }

    public func insertItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            INSERT INTO avelo_inventory_items
            (id, company_id, code, name, unit, alternate_unit, valuation_method, is_active,
             opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown,
             reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.companyId.uuidString),
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .real(item.openingQuantity),
                .integer(item.openingRatePaise),
                .real(item.gstRate),
                .optionalText(item.stockGroup),
                .optionalText(item.stockCategory),
                .optionalText(item.godown),
                .optionalReal(item.reorderLevel),
                .optionalInteger(item.priceLevel1Paise),
                .optionalInteger(item.priceLevel2Paise),
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
            UPDATE avelo_inventory_items SET
                code = ?, name = ?, unit = ?, alternate_unit = ?, valuation_method = ?, is_active = ?,
                opening_quantity = ?, opening_rate_paise = ?, gst_rate = ?,
                stock_group = ?, stock_category = ?, godown = ?, reorder_level = ?,
                price_level1_paise = ?, price_level2_paise = ?, barcode = ?, hsn_sac = ?, is_archived = ?, linked_account_id = ?
            WHERE id = ?
            """,
            [
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .real(item.openingQuantity),
                .integer(item.openingRatePaise),
                .real(item.gstRate),
                .optionalText(item.stockGroup),
                .optionalText(item.stockCategory),
                .optionalText(item.godown),
                .optionalReal(item.reorderLevel),
                .optionalInteger(item.priceLevel1Paise),
                .optionalInteger(item.priceLevel2Paise),
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
            "UPDATE avelo_inventory_items SET is_active = 0 WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    public func insertMovement(_ m: StockMovement) throws {
        try db.execute(
            """
            INSERT INTO avelo_stock_movements
            (id, company_id, item_id, voucher_id, date, movement_type, quantity,
             unit_cost_paise, total_value_paise, reference_voucher_number, batch_number,
             manufacture_date, expiry_date, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(m.id.uuidString),
                .text(m.companyId.uuidString),
                .text(m.itemId.uuidString),
                .optionalText(m.voucherId?.uuidString),
                .date(m.date),
                .text(m.movementType.rawValue),
                .real(m.quantity),
                .integer(m.unitCostPaise),
                .integer(m.totalValuePaise),
                .optionalText(m.referenceVoucherNumber),
                .optionalText(m.batchNumber),
                .optionalDate(m.manufactureDate),
                .optionalDate(m.expiryDate),
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
                   unit_cost_paise, total_value_paise, reference_voucher_number, batch_number,
                   manufacture_date, expiry_date, reason, created_at
            FROM avelo_stock_movements
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
        public let inQty: Double
        public let outQty: Double
        public let adjustmentQty: Double
        public let inValuePaise: Int64
        public let outValuePaise: Int64
        public let onHandQty: Double
        public let onHandValuePaise: Int64
    }

    public func runningBalance(itemId: InventoryItem.ID, asOf: Date) throws -> ItemBalance {
        let asOfStr = DateFormatters.formatIsoDate(asOf)
        // Inbound types: in, opening, purchase, saleReturn, adjustmentIn
        // Outbound types: out, sale, purchaseReturn, adjustmentOut
        // Neutral/net types: adjustment
        let row: (Double, Double, Double, Int64, Int64, Double)? = try db.queryOne(
            """
            SELECT
                COALESCE(SUM(CASE WHEN movement_type IN ('in','opening','purchase','saleReturn','adjustmentIn')
                                  THEN quantity ELSE 0 END), 0) AS in_q,
                COALESCE(SUM(CASE WHEN movement_type IN ('out','sale','purchaseReturn','adjustmentOut')
                                  THEN quantity ELSE 0 END), 0) AS out_q,
                COALESCE(SUM(CASE WHEN movement_type = 'adjustment'
                                  THEN quantity ELSE 0 END), 0) AS adj_q,
                COALESCE(SUM(CASE WHEN movement_type IN ('in','opening','purchase','saleReturn','adjustmentIn')
                                  THEN total_value_paise ELSE 0 END), 0) AS in_v,
                COALESCE(SUM(CASE WHEN movement_type IN ('out','sale','purchaseReturn','adjustmentOut')
                                  THEN total_value_paise ELSE 0 END), 0) AS out_v,
                COALESCE(SUM(CASE
                    WHEN movement_type IN ('in','opening','purchase','saleReturn','adjustmentIn')  THEN  quantity
                    WHEN movement_type IN ('out','sale','purchaseReturn','adjustmentOut')          THEN -quantity
                    WHEN movement_type = 'adjustment'                                             THEN  quantity
                    ELSE 0 END), 0) AS on_hand
            FROM avelo_stock_movements
            WHERE item_id = ? AND date <= ?
            """,
            bind: [.text(itemId.uuidString), .text(asOfStr)]
        ) { r in (r.real(0), r.real(1), r.real(2), r.int(3), r.int(4), r.real(5)) }
        let inQty   = row?.0 ?? 0
        let outQty  = row?.1 ?? 0
        let adjQty  = row?.2 ?? 0
        let inVal   = row?.3 ?? 0
        let outVal  = row?.4 ?? 0
        let onHand  = row?.5 ?? 0
        let onHandVal = inVal - outVal
        assert(inVal <= Int64.max / 2)
        assert(outVal <= Int64.max / 2)
        assert(onHandVal <= Int64.max / 2)
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
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_inventory_items.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_inventory_items.company_id")
        let vm = ValuationMethod(rawValue: r.text("valuation_method")) ?? .fifo
        return InventoryItem(
            id: id,
            companyId: companyId,
            code: r.text("code"),
            name: r.text("name"),
            unit: r.text("unit"),
            alternateUnit: r.optionalText("alternate_unit"),
            valuationMethod: vm,
            isActive: r.bool("is_active"),
            openingQuantity: r.real("opening_quantity"),
            openingRatePaise: r.int("opening_rate_paise"),
            gstRate: r.real("gst_rate"),
            stockGroup: r.optionalText("stock_group"),
            stockCategory: r.optionalText("stock_category"),
            godown: r.optionalText("godown"),
            reorderLevel: r.optionalReal("reorder_level"),
            priceLevel1Paise: r.optionalReal("price_level1_paise").map(Int64.init),
            priceLevel2Paise: r.optionalReal("price_level2_paise").map(Int64.init),
            barcode: r.optionalText("barcode"),
            hsnSac: r.optionalText("hsn_sac"),
            isArchived: r.bool("is_archived"),
            linkedAccountId: try UUIDParsing.optional(r.optionalText("linked_account_id"), field: "avelo_inventory_items.linked_account_id"),
            createdAt: try r.timestamp("created_at")
        )
    }

    static func rowToMovement(_ r: Row) throws -> StockMovement {
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_stock_movements.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_stock_movements.company_id")
        let itemId = try UUIDParsing.required(r.text("item_id"), field: "avelo_stock_movements.item_id")
        let voucherId = try UUIDParsing.optional(r.optionalText("voucher_id"), field: "avelo_stock_movements.voucher_id")
        let mt = MovementType(rawValue: r.text("movement_type")) ?? .adjustment
        return StockMovement(
            id: id,
            companyId: companyId,
            itemId: itemId,
            date: r.date("date"),
            movementType: mt,
            quantity: r.real("quantity"),
            unitCostPaise: r.int("unit_cost_paise"),
            totalValuePaise: r.int("total_value_paise"),
            voucherId: voucherId,
            referenceVoucherNumber: r.optionalText("reference_voucher_number"),
            batchNumber: r.optionalText("batch_number"),
            manufactureDate: r.optionalDate("manufacture_date"),
            expiryDate: r.optionalDate("expiry_date"),
            reason: r.optionalText("reason"),
            createdAt: try r.timestamp("created_at")
        )
    }
}
