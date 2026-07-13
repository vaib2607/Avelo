import Foundation

public enum ValuationMethod: String, CaseIterable, Sendable, Codable, Identifiable {
    case fifo
    case weightedAverage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
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

    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: String,
                name: String,
                unit: String,
                alternateUnit: String? = nil,
                baseUnitsPerAlternateUnit: ExactQuantity? = nil,
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
                hsnCode: String? = nil,
                gstRateBps: Int? = nil,
                gstCessRateBps: Int? = nil,
                gstTaxability: GSTTaxability = .taxable,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name
        self.unit = unit
        self.alternateUnit = alternateUnit
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
    }
}

public enum MovementType: String, CaseIterable, Sendable, Codable, Identifiable {
    case stockIn = "in"
    case stockOut = "out"
    case adjustment

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stockIn:    return "In"
        case .stockOut:   return "Out"
        case .adjustment: return "Adjustment"
        }
    }
}

extension InventoryItem {
    public typealias MovementType = Avelo.MovementType

    public enum MovementDirection: String, Sendable, Codable {
        case `in`
        case out
        case none
    }

    public func direction(for type: MovementType) -> MovementDirection {
        switch type {
        case .stockIn:    return .in
        case .stockOut:   return .out
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
    public var quantity: ExactQuantity
    public var enteredUnit: String?
    public var unitCostPaise: Int64
    public var totalValuePaise: Int64
    public var reversedMovementId: StockMovement.ID?
    public var referenceVoucherNumber: String?
    public var reason: String?
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                itemId: InventoryItem.ID,
                date: Date,
                movementType: MovementType,
                quantity: ExactQuantity,
                unitCostPaise: Int64,
                totalValuePaise: Int64,
                voucherId: Voucher.ID? = nil,
                enteredUnit: String? = nil,
                reversedMovementId: StockMovement.ID? = nil,
                referenceVoucherNumber: String? = nil,
                reason: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.itemId = itemId
        self.voucherId = voucherId
        self.date = date
        self.movementType = movementType
        self.quantity = quantity
        self.enteredUnit = enteredUnit
        self.unitCostPaise = unitCostPaise
        self.totalValuePaise = totalValuePaise
        self.reversedMovementId = reversedMovementId
        self.referenceVoucherNumber = referenceVoucherNumber
        self.reason = reason
        self.createdAt = createdAt
    }

    public var notes: String? { reason }

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
}
