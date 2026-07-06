import Foundation

public struct InventoryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private static let itemColumns = "id, company_id, code, name, unit, alternate_unit, alt_unit_base_numerator, alt_unit_base_denominator, valuation_method, is_active, created_at"
    private static let movementColumns = "id, company_id, item_id, voucher_id, date, movement_type, quantity, quantity_numerator, quantity_denominator, entered_unit, unit_cost_paise, total_value_paise, reversed_movement_id, reference_voucher_number, reason, created_at"

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
            (id, company_id, code, name, unit, alternate_unit, alt_unit_base_numerator, alt_unit_base_denominator, valuation_method, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.companyId.uuidString),
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.numerator),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.denominator),
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
                code = ?, name = ?, unit = ?, alternate_unit = ?, alt_unit_base_numerator = ?, alt_unit_base_denominator = ?, valuation_method = ?, is_active = ?
            WHERE id = ?
            """,
            [
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.numerator),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.denominator),
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
             quantity_numerator, quantity_denominator, entered_unit,
             unit_cost_paise, total_value_paise, reversed_movement_id, reference_voucher_number, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(m.id.uuidString),
                .text(m.companyId.uuidString),
                .text(m.itemId.uuidString),
                .optionalText(m.voucherId?.uuidString),
                .date(m.date),
                .text(m.movementType.rawValue),
                .integer(m.quantity.wholeValue ?? m.quantity.numerator),
                .integer(m.quantity.numerator),
                .integer(m.quantity.denominator),
                .optionalText(m.enteredUnit),
                .integer(m.unitCostPaise),
                .integer(m.totalValuePaise),
                .optionalText(m.reversedMovementId?.uuidString),
                .optionalText(m.referenceVoucherNumber),
                .optionalText(m.reason),
                .timestamp(m.createdAt)
            ]
        )
    }

    public func findMovement(id: StockMovement.ID) throws -> StockMovement? {
        try db.queryOne(
            "SELECT \(Self.movementColumns) FROM avelo_stock_movements WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToMovement($0) }
    }

    public func updateMovement(_ movement: StockMovement) throws {
        try db.execute(
            """
            UPDATE avelo_stock_movements SET
                item_id = ?, voucher_id = ?, date = ?, movement_type = ?, quantity = ?,
                quantity_numerator = ?, quantity_denominator = ?, entered_unit = ?,
                unit_cost_paise = ?, total_value_paise = ?, reversed_movement_id = ?, reference_voucher_number = ?, reason = ?
            WHERE id = ? AND company_id = ?
            """,
            [
                .text(movement.itemId.uuidString),
                .optionalText(movement.voucherId?.uuidString),
                .date(movement.date),
                .text(movement.movementType.rawValue),
                .integer(movement.quantity.wholeValue ?? movement.quantity.numerator),
                .integer(movement.quantity.numerator),
                .integer(movement.quantity.denominator),
                .optionalText(movement.enteredUnit),
                .integer(movement.unitCostPaise),
                .integer(movement.totalValuePaise),
                .optionalText(movement.reversedMovementId?.uuidString),
                .optionalText(movement.referenceVoucherNumber),
                .optionalText(movement.reason),
                .text(movement.id.uuidString),
                .text(movement.companyId.uuidString)
            ]
        )
    }

    public func updateMovementTotalValue(id: StockMovement.ID, companyId: Company.ID, totalValuePaise: Int64) throws {
        try db.execute(
            "UPDATE avelo_stock_movements SET total_value_paise = ? WHERE id = ? AND company_id = ?",
            [.integer(totalValuePaise), .text(id.uuidString), .text(companyId.uuidString)]
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
        public let inQuantity: ExactQuantity
        public let outQuantity: ExactQuantity
        public let adjustmentQuantity: ExactQuantity
        public let inValuePaise: Int64
        public let outValuePaise: Int64
        public let onHandQuantity: SignedExactQuantity
        public let onHandValuePaise: Int64

        public var inQty: Int64 { inQuantity.wholeValue ?? 0 }
        public var outQty: Int64 { outQuantity.wholeValue ?? 0 }
        public var adjustmentQty: Int64 { adjustmentQuantity.wholeValue ?? 0 }
        public var onHandQty: Int64 { onHandQuantity.numerator >= 0 ? (onHandQuantity.magnitude.wholeValue ?? 0) : 0 }
    }

    public func runningBalance(itemId: InventoryItem.ID, asOf: Date) throws -> ItemBalance {
        let companyId = try findCompanyId(for: itemId)
        let item = try findItemById(itemId)
        let movements = try listMovementsChronologically(companyId: companyId, itemId: itemId, asOf: asOf)
        let snapshot = try InventoryValuationEngine().replay(movements: movements, valuationMethod: item?.valuationMethod ?? .fifo)
        return ItemBalance(
            itemId: itemId,
            inQuantity: snapshot.inboundQuantity,
            outQuantity: snapshot.outboundQuantity,
            adjustmentQuantity: snapshot.adjustmentQuantity,
            inValuePaise: snapshot.inboundValuePaise,
            outValuePaise: snapshot.outboundValuePaise,
            onHandQuantity: snapshot.onHandQuantity,
            onHandValuePaise: snapshot.onHandValuePaise
        )
    }

    public func listMovementsChronologically(companyId: Company.ID, itemId: InventoryItem.ID, asOf: Date? = nil) throws -> [StockMovement] {
        let movements = try listMovements(filter: .init(companyId: companyId, itemId: itemId, toDate: asOf, limit: Int.max, offset: 0))
        return movements.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func rowToItem(_ r: Row) throws -> InventoryItem {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_inventory_items.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_inventory_items.company_id")
        let vm: ValuationMethod = try r.enumValue("valuation_method")
        let altUnit = try r.checkedOptionalText("alternate_unit")
        let altBaseNumerator = try r.checkedOptionalInt("alt_unit_base_numerator")
        let altBaseDenominator = try r.checkedOptionalInt("alt_unit_base_denominator")
        return InventoryItem(
            id: id,
            companyId: companyId,
            code: try r.requiredText("code"),
            name: try r.requiredText("name"),
            unit: try r.requiredText("unit"),
            alternateUnit: altUnit,
            baseUnitsPerAlternateUnit: try {
                guard let altBaseNumerator, let altBaseDenominator else { return nil }
                return try ExactQuantity(numerator: altBaseNumerator, denominator: altBaseDenominator)
            }(),
            valuationMethod: vm,
            isActive: try r.requiredBool("is_active"),
            createdAt: try r.timestamp("created_at")
        )
    }

    static func rowToMovement(_ r: Row) throws -> StockMovement {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_stock_movements.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_stock_movements.company_id")
        let itemId = try UUIDParsing.required(r.requiredText("item_id"), field: "avelo_stock_movements.item_id")
        let voucherId = try UUIDParsing.optional(try r.checkedOptionalText("voucher_id"), field: "avelo_stock_movements.voucher_id")
        let reversedMovementId = try UUIDParsing.optional(try r.checkedOptionalText("reversed_movement_id"), field: "avelo_stock_movements.reversed_movement_id")
        let mt: MovementType = try r.enumValue("movement_type")
        let quantityNumerator = try r.checkedOptionalInt("quantity_numerator") ?? r.int("quantity")
        let quantityDenominator = try r.checkedOptionalInt("quantity_denominator") ?? 1
        return StockMovement(
            id: id,
            companyId: companyId,
            itemId: itemId,
            date: try r.requiredDate("date"),
            movementType: mt,
            quantity: try ExactQuantity(numerator: quantityNumerator, denominator: quantityDenominator),
            unitCostPaise: try r.requiredInt("unit_cost_paise"),
            totalValuePaise: try r.requiredInt("total_value_paise"),
            voucherId: voucherId,
            enteredUnit: try r.checkedOptionalText("entered_unit"),
            reversedMovementId: reversedMovementId,
            referenceVoucherNumber: try r.checkedOptionalText("reference_voucher_number"),
            reason: try r.checkedOptionalText("reason"),
            createdAt: try r.timestamp("created_at")
        )
    }

    private func findCompanyId(for itemId: InventoryItem.ID) throws -> Company.ID {
        guard let item = try findItemById(itemId) else {
            throw AppError.notFound("Inventory item")
        }
        return item.companyId
    }
}
