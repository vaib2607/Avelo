import Foundation

public struct InventoryRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

<<<<<<< HEAD
    private static let itemColumns = "id, company_id, code, name, unit, alternate_unit, alt_unit_base_numerator, alt_unit_base_denominator, valuation_method, is_active, hsn_code, gst_rate_bps, gst_cess_rate_bps, gst_taxability, created_at"
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
=======
    public func findItemById(_ id: InventoryItem.ID) throws -> InventoryItem? {
        try db.queryOne(
            "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE id = ?",
>>>>>>> origin/main
            bind: [.text(id.uuidString)]
        ) { try Self.rowToItem($0) }
    }

    public func findItemByCode(_ code: String, companyId: Company.ID) throws -> InventoryItem? {
        try db.queryOne(
<<<<<<< HEAD
            "SELECT \(Self.itemColumns) FROM avelo_inventory_items WHERE company_id = ? AND code = ?",
=======
            "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE company_id = ? AND code = ?",
>>>>>>> origin/main
            bind: [.text(companyId.uuidString), .text(code)]
        ) { try Self.rowToItem($0) }
    }

    public func listItemsForCompany(_ companyId: Company.ID, includeInactive: Bool = false) throws -> [InventoryItem] {
<<<<<<< HEAD
        let sql = "SELECT \(Self.itemColumns) FROM avelo_inventory_items WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1") ORDER BY code COLLATE NOCASE"
=======
        let sql = "SELECT id, company_id, code, name, unit, alternate_unit, valuation_method, is_active, opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown, reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at FROM avelo_inventory_items WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1") ORDER BY code COLLATE NOCASE"
>>>>>>> origin/main
        return try db.query(sql, bind: [.text(companyId.uuidString)]) { try Self.rowToItem($0) }
    }

    public func listItems(companyId: Company.ID, includeArchived: Bool = false) throws -> [InventoryItem] {
        try listItemsForCompany(companyId, includeInactive: includeArchived)
    }

<<<<<<< HEAD
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

=======
>>>>>>> origin/main
    public func findItem(id: InventoryItem.ID) throws -> InventoryItem? {
        try findItemById(id)
    }

    public func archiveItem(_ id: InventoryItem.ID) throws {
        try disableItem(id)
    }

    public func setItemAccount(itemId: InventoryItem.ID, accountId: Account.ID) throws {
<<<<<<< HEAD
        _ = (itemId, accountId)
        throw AppError.featureUnavailable("Inventory-item account linking is deferred outside the frozen schema.")
=======
        try db.execute(
            "UPDATE avelo_inventory_items SET linked_account_id = ? WHERE id = ?",
            [.text(accountId.uuidString), .text(itemId.uuidString)]
        )
>>>>>>> origin/main
    }

    public func insertItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            INSERT INTO avelo_inventory_items
<<<<<<< HEAD
            (id, company_id, code, name, unit, alternate_unit, alt_unit_base_numerator, alt_unit_base_denominator, valuation_method, is_active, hsn_code, gst_rate_bps, gst_cess_rate_bps, gst_taxability, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
=======
            (id, company_id, code, name, unit, alternate_unit, valuation_method, is_active,
             opening_quantity, opening_rate_paise, gst_rate, stock_group, stock_category, godown,
             reorder_level, price_level1_paise, price_level2_paise, barcode, hsn_sac, is_archived, linked_account_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
>>>>>>> origin/main
            """,
            [
                .text(item.id.uuidString),
                .text(item.companyId.uuidString),
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
<<<<<<< HEAD
                .optionalInteger(item.baseUnitsPerAlternateUnit?.numerator),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.denominator),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .optionalText(item.hsnCode),
                .optionalInteger(item.gstRateBps.map(Int64.init)),
                .optionalInteger(item.gstCessRateBps.map(Int64.init)),
                .text(item.gstTaxability.rawValue),
=======
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
>>>>>>> origin/main
                .timestamp(item.createdAt)
            ]
        )
    }

    public func updateItem(_ item: InventoryItem) throws {
        try db.execute(
            """
            UPDATE avelo_inventory_items SET
<<<<<<< HEAD
                code = ?, name = ?, unit = ?, alternate_unit = ?, alt_unit_base_numerator = ?, alt_unit_base_denominator = ?, valuation_method = ?, is_active = ?,
                hsn_code = ?, gst_rate_bps = ?, gst_cess_rate_bps = ?, gst_taxability = ?
=======
                code = ?, name = ?, unit = ?, alternate_unit = ?, valuation_method = ?, is_active = ?,
                opening_quantity = ?, opening_rate_paise = ?, gst_rate = ?,
                stock_group = ?, stock_category = ?, godown = ?, reorder_level = ?,
                price_level1_paise = ?, price_level2_paise = ?, barcode = ?, hsn_sac = ?, is_archived = ?, linked_account_id = ?
>>>>>>> origin/main
            WHERE id = ?
            """,
            [
                .text(item.code),
                .text(item.name),
                .text(item.unit),
                .optionalText(item.alternateUnit),
<<<<<<< HEAD
                .optionalInteger(item.baseUnitsPerAlternateUnit?.numerator),
                .optionalInteger(item.baseUnitsPerAlternateUnit?.denominator),
                .text(item.valuationMethod.rawValue),
                .bool(item.isActive),
                .optionalText(item.hsnCode),
                .optionalInteger(item.gstRateBps.map(Int64.init)),
                .optionalInteger(item.gstCessRateBps.map(Int64.init)),
                .text(item.gstTaxability.rawValue),
=======
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
>>>>>>> origin/main
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
<<<<<<< HEAD
             quantity_numerator, quantity_denominator, entered_unit,
             unit_cost_paise, total_value_paise, reversed_movement_id, reference_voucher_number, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
=======
             unit_cost_paise, total_value_paise, reference_voucher_number, batch_number,
             manufacture_date, expiry_date, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
>>>>>>> origin/main
            """,
            [
                .text(m.id.uuidString),
                .text(m.companyId.uuidString),
                .text(m.itemId.uuidString),
                .optionalText(m.voucherId?.uuidString),
                .date(m.date),
                .text(m.movementType.rawValue),
<<<<<<< HEAD
                .integer(m.quantity.wholeValue ?? m.quantity.numerator),
                .integer(m.quantity.numerator),
                .integer(m.quantity.denominator),
                .optionalText(m.enteredUnit),
                .integer(m.unitCostPaise),
                .integer(m.totalValuePaise),
                .optionalText(m.reversedMovementId?.uuidString),
                .optionalText(m.referenceVoucherNumber),
=======
                .real(m.quantity),
                .integer(m.unitCostPaise),
                .integer(m.totalValuePaise),
                .optionalText(m.referenceVoucherNumber),
                .optionalText(m.batchNumber),
                .optionalDate(m.manufactureDate),
                .optionalDate(m.expiryDate),
>>>>>>> origin/main
                .optionalText(m.reason),
                .timestamp(m.createdAt)
            ]
        )
    }

<<<<<<< HEAD
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

=======
>>>>>>> origin/main
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
<<<<<<< HEAD
            SELECT \(Self.movementColumns)
=======
            SELECT id, company_id, item_id, voucher_id, date, movement_type, quantity,
                   unit_cost_paise, total_value_paise, reference_voucher_number, batch_number,
                   manufacture_date, expiry_date, reason, created_at
>>>>>>> origin/main
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

<<<<<<< HEAD
    /// Stock movements linked to a single voucher (AVL-P0-022), oldest
    /// first. Used by invoice PDF rendering to show a stock detail section
    /// for inventory-linked sales/purchase vouchers.
    public func listMovements(forVoucher voucherId: Voucher.ID) throws -> [StockMovement] {
        try db.query(
            "SELECT \(Self.movementColumns) FROM avelo_stock_movements WHERE voucher_id = ? ORDER BY created_at ASC",
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToMovement($0) }
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
            hsnCode: try r.checkedOptionalText("hsn_code"),
            gstRateBps: r.optionalInt("gst_rate_bps").map(Int.init),
            gstCessRateBps: r.optionalInt("gst_cess_rate_bps").map(Int.init),
            gstTaxability: try r.enumValue("gst_taxability"),
            createdAt: try r.timestamp("created_at")
=======
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
            createdAt: r.timestamp("created_at")
>>>>>>> origin/main
        )
    }

    static func rowToMovement(_ r: Row) throws -> StockMovement {
<<<<<<< HEAD
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_stock_movements.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_stock_movements.company_id")
        let itemId = try UUIDParsing.required(r.requiredText("item_id"), field: "avelo_stock_movements.item_id")
        let voucherId = try UUIDParsing.optional(try r.checkedOptionalText("voucher_id"), field: "avelo_stock_movements.voucher_id")
        let reversedMovementId = try UUIDParsing.optional(try r.checkedOptionalText("reversed_movement_id"), field: "avelo_stock_movements.reversed_movement_id")
        let mt: MovementType = try r.enumValue("movement_type")
        let quantityNumerator = try r.checkedOptionalInt("quantity_numerator") ?? r.int("quantity")
        let quantityDenominator = try r.checkedOptionalInt("quantity_denominator") ?? 1
=======
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_stock_movements.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_stock_movements.company_id")
        let itemId = try UUIDParsing.required(r.text("item_id"), field: "avelo_stock_movements.item_id")
        let voucherId = try UUIDParsing.optional(r.optionalText("voucher_id"), field: "avelo_stock_movements.voucher_id")
        let mt = MovementType(rawValue: r.text("movement_type")) ?? .adjustment
>>>>>>> origin/main
        return StockMovement(
            id: id,
            companyId: companyId,
            itemId: itemId,
<<<<<<< HEAD
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
=======
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
            createdAt: r.timestamp("created_at")
        )
    }
>>>>>>> origin/main
}
