import Foundation

public enum ValuationMethod: String, CaseIterable, Sendable, Codable, Identifiable {
    case fifo
    case weightedAverage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fifo:             return "FIFO (First In First Out)"
        case .weightedAverage:  return "Weighted Average"
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
    public var valuationMethod: ValuationMethod
    public var isActive: Bool
    public let createdAt: Date

    // Extended fields used by inventory flow.
    public var openingQuantity: Double
    public var openingRatePaise: Int64
    public var gstRate: Double
    public var barcode: String?
    public var hsnSac: String?
    public var isArchived: Bool
    public var linkedAccountId: Account.ID?

    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: String,
                name: String,
                unit: String,
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name
        self.unit = unit
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
                valuationMethod: ValuationMethod = .fifo,
                isActive: Bool = true,
                openingQuantity: Double = 0,
                openingRatePaise: Int64 = 0,
                gstRate: Double = 0,
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
        self.valuationMethod = valuationMethod
        self.isActive = isActive
        self.createdAt = createdAt
        self.openingQuantity = openingQuantity
        self.openingRatePaise = openingRatePaise
        self.gstRate = gstRate
        self.barcode = barcode
        self.hsnSac = hsnSac
        self.isArchived = isArchived
        self.linkedAccountId = linkedAccountId
    }
}

public enum MovementType: String, CaseIterable, Sendable, Codable, Identifiable {
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

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
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
        }
    }
}

extension InventoryItem {
    public typealias MovementType = Mally.MovementType
    public enum MovementDirection: String, Sendable, Codable {
        case `in`
        case out
        case none
    }

    public func direction(for type: MovementType) -> MovementDirection {
        switch type {
        case .stockIn, .opening, .purchase, .saleReturn, .adjustmentIn: return .in
        case .stockOut, .purchaseReturn, .sale, .adjustmentOut:        return .out
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
    public var quantity: Int64
    public var unitCostPaise: Int64
    public var totalValuePaise: Int64
    public var referenceVoucherNumber: String?
    public var reason: String?
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                itemId: InventoryItem.ID,
                date: Date,
                movementType: MovementType,
                quantity: Int64,
                unitCostPaise: Int64,
                totalValuePaise: Int64,
                voucherId: Voucher.ID? = nil,
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
        self.unitCostPaise = unitCostPaise
        self.totalValuePaise = totalValuePaise
        self.referenceVoucherNumber = referenceVoucherNumber
        self.reason = reason
        self.createdAt = createdAt
    }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                itemId: InventoryItem.ID,
                date: Date,
                type: MovementType,
                quantity: Double,
                ratePaise: Int64,
                voucherId: Voucher.ID? = nil,
                notes: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.itemId = itemId
        self.voucherId = voucherId
        self.date = date
        self.movementType = type
        self.quantity = Int64(quantity)
        self.unitCostPaise = ratePaise
        self.totalValuePaise = Int64(quantity) * ratePaise
        self.referenceVoucherNumber = nil
        self.reason = notes
        self.createdAt = createdAt
    }

    public var notes: String? { reason }
}
