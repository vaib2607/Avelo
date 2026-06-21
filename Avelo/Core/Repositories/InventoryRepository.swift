import Foundation

public struct InventoryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private static let itemColumns = "id, company_id, code, name, unit, valuation_method, is_active, created_at"
    private static let movementColumns = "id, company_id, item_id, voucher_id, date, movement_type, quantity, unit_cost_paise, total_value_paise, reference_voucher_number, reason, created_at"

    public struct ItemFilter: Sendable {
        public var companyId: Company.ID
        public var includeArchived: Bool
        public var searchText: String?
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    includeArchived: Bool = false,
                    searchText: String? = nil,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.includeArchived = includeArchived
            self.searchText = searchText
            self.limit = limit
            self.offset = offset
        }
    }

    public func findItemById(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT \(Self.itemColumns) FROM avelo_inventory_items WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToItem($0) }
    }

    public func findItemByCode(_ code: String, companyId: Company.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT \(Self.itemColumns) FROM avelo_inventory_items WHERE company_id = ? AND code = ?",
            bind: [.text(companyId.uuidString), .text(code)]
        ) { try Self.rowToItem($0) }
    }

    public func listItemsForCompany(_ companyId: Company.ID, includeInactive: Bool = false) throws -> [InventoryItem] {
        let sql = "SELECT \(Self.itemColumns) FROM avelo_inventory_items WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1") ORDER BY code COLLATE NOCASE"
        return try db.query(sql, bind: [.text(companyId.uuidString)]) { try Self.rowToItem($0) }
    }

    public func listItems(companyId: Company.ID, includeArchived: Bool = false) throws -> [InventoryItem] {
        try listItemsForCompany(companyId, includeInactive: includeArchived)
    }

    public func listItems(companyId: Company.ID, includeArchived: Bool = false, limit: Int, offset: Int = 0) throws -> [InventoryItem] {
        try listItems(filter: .init(companyId: companyId, includeArchived: includeArchived, limit: limit, offset: offset))
    }

    public func listItems(filter: ItemFilter) throws -> [InventoryItem] {
        let built = Self.itemFilterWhereClause(filter)
        let sql = "SELECT \(Self.itemColumns) FROM avelo_inventory_items \(built.sql) ORDER BY code COLLATE NOCASE LIMIT ? OFFSET ?"
        return try db.query(
            sql,
            bind: built.bind + [.integer(Int64(filter.limit)), .integer(Int64(filter.offset))]
        ) { try Self.rowToItem($0) }
    }

    public func countItems(filter: ItemFilter) throws -> Int {
        let built = Self.itemFilterWhereClause(filter)
        return Int(try db.queryOne("SELECT COUNT(*) FROM avelo_inventory_items \(built.sql)", bind: built.bind) { $0.int(0) } ?? 0)
    }

    private static func itemFilterWhereClause(_ filter: ItemFilter) -> (sql: String, bind: [SQLValue]) {
        var sql = "WHERE company_id = ?"
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if !filter.includeArchived {
            sql += " AND is_active = 1"
        }
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            sql += " AND (name LIKE ? OR code LIKE ?)"
            let term = "%\(search)%"
            bind.append(.text(term))
            bind.append(.text(term))
        }
        return (sql, bind)
    }

    public func findItem(id: InventoryItem.ID) throws -> InventoryItem? {
        try findItemById(id)
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try disableItem(id)
    }

    public func setItemAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
        _ = (itemId, accountId)
        throw AppError.featureUnavailable("Inventory-item account linking is deferred outside the frozen schema.")
    }

    public func insertItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            INSERT INTO avelo_inventory_items
            (id, company_id, code, name, unit, valuation_method, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.companyId.uuidString),
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .timestamp(item.createdAt)
            ]
        )
    }

    public func updateItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            UPDATE avelo_inventory_items SET
                code = ?, name = ?, unit = ?, valuation_method = ?, is_active = ?
            WHERE id = ?
            """,
            [
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
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
            SELECT \(Self.movementColumns)
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
        public let inQty: Int64
        public let outQty: Int64
        public let adjustmentQty: Int64
        public let inValuePaise: Int64
        public let outValuePaise: Int64
        public let onHandQty: Int64
        public let onHandValuePaise: Int64
    }

    public func runningBalance(itemId: InventoryItem.ID, asOf: Date) throws -> ItemBalance {
        let row: (Int64, Int64, Int64, Int64, Int64, Int64)? = try db.queryOne(
            """
            SELECT
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0) AS in_q,
                COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS out_q,
                COALESCE(SUM(CASE WHEN movement_type = 'adjustment' THEN quantity ELSE 0 END), 0) AS adj_q,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN total_value_paise ELSE 0 END), 0) AS in_v,
                COALESCE(SUM(CASE WHEN movement_type = 'out' THEN total_value_paise ELSE 0 END), 0) AS out_v,
                COALESCE(SUM(CASE
                    WHEN movement_type = 'in' THEN quantity
                    WHEN movement_type = 'out' THEN -quantity
                    WHEN movement_type = 'adjustment' THEN quantity
                    ELSE 0 END), 0) AS on_hand
            FROM avelo_stock_movements
            WHERE item_id = ? AND date <= ?
            """,
            bind: [.text(itemId.uuidString), .date(asOf)]
        ) { r in (r.int(0), r.int(1), r.int(2), r.int(3), r.int(4), r.int(5)) }
        let inQty = row?.0 ?? 0
        let outQty = row?.1 ?? 0
        let adjQty = row?.2 ?? 0
        let inVal = row?.3 ?? 0
        let outVal = row?.4 ?? 0
        let onHand = row?.5 ?? 0
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
            valuationMethod: vm,
            isActive: r.bool("is_active"),
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
            quantity: r.int("quantity"),
            unitCostPaise: r.int("unit_cost_paise"),
            totalValuePaise: r.int("total_value_paise"),
            voucherId: voucherId,
            referenceVoucherNumber: r.optionalText("reference_voucher_number"),
            reason: r.optionalText("reason"),
            createdAt: try r.timestamp("created_at")
        )
    }
}
