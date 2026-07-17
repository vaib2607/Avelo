import Foundation

public enum ValuationMethod: String, CaseIterable, Sendable, Codable, Identifiable {
    case fifo
    case weightedAverage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
<<<<<<< HEAD
        case .fifo:            return "FIFO (First In First Out)"
        case .weightedAverage: return "Weighted Average"
        }
    }
}

/// Tally item-level GST taxability. RCM/ITC-eligibility flags are deferred
/// (Phase 7 GST rate-setup polish) — taxability is the field that actually
/// gates whether tax gets computed at all, so it ships first.
public enum GSTTaxability: String, CaseIterable, Sendable, Codable, Identifiable {
    case taxable
    case exempt
    case nilRated

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .taxable:  return "Taxable"
        case .exempt:   return "Exempt"
        case .nilRated: return "Nil Rated"
=======
        case .fifo:             return "FIFO (First In First Out)"
        case .weightedAverage:  return "Weighted Average"
>>>>>>> origin/main
        }
    }
}

public struct InventoryItem: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var code: String
    public var name: String
    public var unit: String
    public var alternateUnit: String?
<<<<<<< HEAD
    public var baseUnitsPerAlternateUnit: ExactQuantity?
    public var valuationMethod: ValuationMethod
    public var isActive: Bool
    public var hsnCode: String?
    /// GST rate in basis points (1800 = 18%), matching the full IGST rate —
    /// intra-state splits this into CGST+SGST halves at posting time.
    public var gstRateBps: Int?
    public var gstCessRateBps: Int?
    public var gstTaxability: GSTTaxability
    public let createdAt: Date

=======
    public var valuationMethod: ValuationMethod
    public var isActive: Bool
    public let createdAt: Date

    // Extended fields used by inventory flow.
    public var openingQuantity: Double
    public var openingRatePaise: Int64
    public var gstRate: Double
    public var stockGroup: String?
    public var stockCategory: String?
    public var godown: String?
    public var reorderLevel: Double?
    public var priceLevel1Paise: Int64?
    public var priceLevel2Paise: Int64?
    public var barcode: String?
    public var hsnSac: String?
    public var isArchived: Bool
    public var linkedAccountId: Account.ID?

>>>>>>> origin/main
    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: String,
                name: String,
                unit: String,
                alternateUnit: String? = nil,
<<<<<<< HEAD
                baseUnitsPerAlternateUnit: ExactQuantity? = nil,
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
                hsnCode: String? = nil,
                gstRateBps: Int? = nil,
                gstCessRateBps: Int? = nil,
                gstTaxability: GSTTaxability = .taxable,
=======
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
>>>>>>> origin/main
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name
        self.unit = unit
        self.alternateUnit = alternateUnit
<<<<<<< HEAD
        self.baseUnitsPerAlternateUnit = baseUnitsPerAlternateUnit
        self.valuationMethod = valuationMethod
        self.isActive = isActive
        self.hsnCode = hsnCode
        self.gstRateBps = gstRateBps
        self.gstCessRateBps = gstCessRateBps
        self.gstTaxability = gstTaxability
        self.createdAt = createdAt
    }

    public var alternateUnitDefinition: AlternateUnitDefinition? {
        guard let alternateUnit, let baseUnitsPerAlternateUnit else { return nil }
        return try? AlternateUnitDefinition(alternateUnit: alternateUnit, baseUnitsPerAlternateUnit: baseUnitsPerAlternateUnit)
=======
        self.valuationMethod = valuationMethod
        self.isActive = isActive
        self.createdAt = createdAt
        self.openingQuantity = 0
        self.openingRatePaise = 0
        self.gstRate = 0
        self.barcode = nil
        self.hsnSac = nil
        self.isArchived = false
        self.linkedAccountId = nil
    }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: String,
                name: String,
                unit: String,
                alternateUnit: String? = nil,
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
                openingQuantity: Double = 0,
                openingRatePaise: Int64 = 0,
                gstRate: Double = 0,
                stockGroup: String? = nil,
                stockCategory: String? = nil,
                godown: String? = nil,
                reorderLevel: Double? = nil,
                priceLevel1Paise: Int64? = nil,
                priceLevel2Paise: Int64? = nil,
                barcode: String? = nil,
                hsnSac: String? = nil,
                isArchived: Bool = false,
                linkedAccountId: Account.ID? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name
        self.unit = unit
        self.alternateUnit = alternateUnit
        self.valuationMethod = valuationMethod
        self.isActive = isActive
        self.createdAt = createdAt
        self.openingQuantity = openingQuantity
        self.openingRatePaise = openingRatePaise
        self.gstRate = gstRate
        self.stockGroup = stockGroup
        self.stockCategory = stockCategory
        self.godown = godown
        self.reorderLevel = reorderLevel
        self.priceLevel1Paise = priceLevel1Paise
        self.priceLevel2Paise = priceLevel2Paise
        self.barcode = barcode
        self.hsnSac = hsnSac
        self.isArchived = isArchived
        self.linkedAccountId = linkedAccountId
>>>>>>> origin/main
    }
}

public enum MovementType: String, CaseIterable, Sendable, Codable, Identifiable {
<<<<<<< HEAD
    case stockIn = "in"
    case stockOut = "out"
    case adjustment
=======
    case stockIn      = "in"
    case stockOut     = "out"
    case adjustment
    case opening
    case purchase
    case purchaseReturn
    case sale
    case saleReturn
    case adjustmentIn
    case adjustmentOut
>>>>>>> origin/main

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
<<<<<<< HEAD
        case .stockIn:    return "In"
        case .stockOut:   return "Out"
        case .adjustment: return "Adjustment"
=======
        case .stockIn:        return "In"
        case .stockOut:       return "Out"
        case .adjustment:     return "Adjustment"
        case .opening:        return "Opening"
        case .purchase:       return "Purchase"
        case .purchaseReturn: return "Purchase Return"
        case .sale:           return "Sale"
        case .saleReturn:     return "Sale Return"
        case .adjustmentIn:   return "Adjustment In"
        case .adjustmentOut:  return "Adjustment Out"
>>>>>>> origin/main
        }
    }
}

extension InventoryItem {
    public typealias MovementType = Avelo.MovementType
<<<<<<< HEAD

=======
>>>>>>> origin/main
    public enum MovementDirection: String, Sendable, Codable {
        case `in`
        case out
        case none
    }

    public func direction(for type: MovementType) -> MovementDirection {
        switch type {
<<<<<<< HEAD
        case .stockIn:    return .in
        case .stockOut:   return .out
=======
        case .stockIn, .opening, .purchase, .saleReturn, .adjustmentIn: return .in
        case .stockOut, .purchaseReturn, .sale, .adjustmentOut:        return .out
>>>>>>> origin/main
        case .adjustment: return .none
        }
    }
}

public struct StockMovement: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var itemId: InventoryItem.ID
    public var voucherId: Voucher.ID?
    public var date: Date
    public var movementType: MovementType
<<<<<<< HEAD
    public var quantity: ExactQuantity
    public var enteredUnit: String?
    public var unitCostPaise: Int64
    public var totalValuePaise: Int64
    public var reversedMovementId: StockMovement.ID?
    public var referenceVoucherNumber: String?
=======
    public var quantity: Double
    public var unitCostPaise: Int64
    public var totalValuePaise: Int64
    public var referenceVoucherNumber: String?
    public var batchNumber: String?
    public var manufactureDate: Date?
    public var expiryDate: Date?
>>>>>>> origin/main
    public var reason: String?
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                itemId: InventoryItem.ID,
                date: Date,
                movementType: MovementType,
<<<<<<< HEAD
                quantity: ExactQuantity,
                unitCostPaise: Int64,
                totalValuePaise: Int64,
                voucherId: Voucher.ID? = nil,
                enteredUnit: String? = nil,
                reversedMovementId: StockMovement.ID? = nil,
                referenceVoucherNumber: String? = nil,
=======
                quantity: Double,
                unitCostPaise: Int64,
                totalValuePaise: Int64,
                voucherId: Voucher.ID? = nil,
                referenceVoucherNumber: String? = nil,
                batchNumber: String? = nil,
                manufactureDate: Date? = nil,
                expiryDate: Date? = nil,
>>>>>>> origin/main
                reason: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.itemId = itemId
        self.voucherId = voucherId
        self.date = date
        self.movementType = movementType
        self.quantity = quantity
<<<<<<< HEAD
        self.enteredUnit = enteredUnit
        self.unitCostPaise = unitCostPaise
        self.totalValuePaise = totalValuePaise
        self.reversedMovementId = reversedMovementId
        self.referenceVoucherNumber = referenceVoucherNumber
=======
        self.unitCostPaise = unitCostPaise
        self.totalValuePaise = totalValuePaise
        self.referenceVoucherNumber = referenceVoucherNumber
        self.batchNumber = batchNumber
        self.manufactureDate = manufactureDate
        self.expiryDate = expiryDate
>>>>>>> origin/main
        self.reason = reason
        self.createdAt = createdAt
    }

    public var notes: String? { reason }
<<<<<<< HEAD

    public var quantityDisplayString: String { quantity.displayString }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                itemId: InventoryItem.ID,
                date: Date,
                movementType: MovementType,
                quantity: Int64,
                unitCostPaise: Int64,
                totalValuePaise: Int64,
                voucherId: Voucher.ID? = nil,
                enteredUnit: String? = nil,
                reversedMovementId: StockMovement.ID? = nil,
                referenceVoucherNumber: String? = nil,
                reason: String? = nil,
                createdAt: Date = Date()) {
        try! self.init(
            id: id,
            companyId: companyId,
            itemId: itemId,
            date: date,
            movementType: movementType,
            quantity: ExactQuantity(numerator: quantity, denominator: 1),
            unitCostPaise: unitCostPaise,
            totalValuePaise: totalValuePaise,
            voucherId: voucherId,
            enteredUnit: enteredUnit,
            reversedMovementId: reversedMovementId,
            referenceVoucherNumber: referenceVoucherNumber,
            reason: reason,
            createdAt: createdAt
        )
    }
=======
>>>>>>> origin/main
}
