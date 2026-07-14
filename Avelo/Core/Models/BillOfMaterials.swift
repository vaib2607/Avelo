import Foundation

public struct BillOfMaterials: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var assemblyItemId: InventoryItem.ID
    public var outputQuantity: ExactQuantity
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                assemblyItemId: InventoryItem.ID,
                outputQuantity: ExactQuantity,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.assemblyItemId = assemblyItemId
        self.outputQuantity = outputQuantity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BOMComponent: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var bomId: BillOfMaterials.ID
    public var componentItemId: InventoryItem.ID
    public var quantity: ExactQuantity
    public var lineOrder: Int

    public init(id: ID = UUID(),
                companyId: Company.ID,
                bomId: BillOfMaterials.ID,
                componentItemId: InventoryItem.ID,
                quantity: ExactQuantity,
                lineOrder: Int = 0) {
        self.id = id
        self.companyId = companyId
        self.bomId = bomId
        self.componentItemId = componentItemId
        self.quantity = quantity
        self.lineOrder = lineOrder
    }
}

/// Formats the decimal-only quantities accepted by BOM setup without ever
/// round-tripping through `Double`. `ExactQuantity` reduces fractions (for
/// example, 0.125 becomes 1/8), so BOM display expands factors of 2 and 5
/// back to a terminating base-10 representation before showing the value.
public enum BOMQuantityFormat {
    public static func display(_ quantity: ExactQuantity) -> String {
        guard !quantity.isZero else { return "0" }

        var remainingDenominator = quantity.denominator
        var twos = 0
        var fives = 0
        while remainingDenominator % 2 == 0 {
            remainingDenominator /= 2
            twos += 1
        }
        while remainingDenominator % 5 == 0 {
            remainingDenominator /= 5
            fives += 1
        }
        guard remainingDenominator == 1 else {
            return "\(quantity.numerator)/\(quantity.denominator)"
        }

        let scale = max(twos, fives)
        var scaledNumerator = quantity.numerator
        for _ in 0..<(scale - twos) {
            guard let value = multipliedWithoutOverflow(scaledNumerator, by: 2) else {
                return "\(quantity.numerator)/\(quantity.denominator)"
            }
            scaledNumerator = value
        }
        for _ in 0..<(scale - fives) {
            guard let value = multipliedWithoutOverflow(scaledNumerator, by: 5) else {
                return "\(quantity.numerator)/\(quantity.denominator)"
            }
            scaledNumerator = value
        }

        var decimalScale: Int64 = 1
        for _ in 0..<scale {
            guard let value = multipliedWithoutOverflow(decimalScale, by: 10) else {
                return "\(quantity.numerator)/\(quantity.denominator)"
            }
            decimalScale = value
        }

        let whole = scaledNumerator / decimalScale
        let remainder = scaledNumerator % decimalScale
        guard remainder != 0 else { return "\(whole)" }

        var fractional = String(remainder)
        if fractional.count < scale {
            fractional = String(repeating: "0", count: scale - fractional.count) + fractional
        }
        while fractional.last == "0" {
            fractional.removeLast()
        }
        return "\(whole).\(fractional)"
    }

    private static func multipliedWithoutOverflow(_ value: Int64, by multiplier: Int64) -> Int64? {
        let result = value.multipliedReportingOverflow(by: multiplier)
        return result.overflow ? nil : result.partialValue
    }
}
