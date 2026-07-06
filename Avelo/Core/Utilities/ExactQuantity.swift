import Foundation

public struct ExactQuantity: Hashable, Sendable, Codable, Comparable {
    public let numerator: Int64
    public let denominator: Int64

    public init(numerator: Int64, denominator: Int64) throws {
        guard denominator != 0 else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Quantity denominator cannot be zero."))
        }
        guard denominator > 0 else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Quantity denominator must be positive."))
        }
        guard numerator >= 0 else {
            throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Quantity cannot be negative."))
        }
        let divisor = Self.gcd(Self.absInt64(numerator), denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    public static func whole(_ value: Int64) throws -> ExactQuantity {
        try ExactQuantity(numerator: value, denominator: 1)
    }

    public static func parse(decimal text: String) throws -> ExactQuantity {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Quantity is required."))
        }
        guard !trimmed.hasPrefix("-") else {
            throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Quantity must be greater than zero."))
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              let wholePart = Int64(parts[0].isEmpty ? "0" : String(parts[0])) else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Invalid quantity."))
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.allSatisfy(\.isNumber) else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Invalid quantity."))
        }
        let denominator = try Self.pow10(fraction.count)
        let scaledWhole = try CheckedMath.multiply(wholePart, denominator, context: "scaling quantity whole part")
        let fractionValue = Int64(fraction) ?? 0
        let numerator = try CheckedMath.add(scaledWhole, fractionValue, context: "building quantity numerator")
        return try ExactQuantity(numerator: numerator, denominator: denominator)
    }

    public var isWhole: Bool { denominator == 1 }
    public var isZero: Bool { numerator == 0 }

    public var wholeValue: Int64? {
        guard denominator == 1 else { return nil }
        return numerator
    }

    public var displayString: String {
        if denominator == 1 { return "\(numerator)" }
        let sign = numerator < 0 ? "-" : ""
        let absolute = Self.absInt64(numerator)
        let whole = absolute / denominator
        let remainder = absolute % denominator
        var digits = String(remainder)
        let targetWidth = String(denominator).count - 1
        if digits.count < targetWidth {
            digits = String(repeating: "0", count: targetWidth - digits.count) + digits
        }
        while digits.last == "0" {
            digits.removeLast()
        }
        guard !digits.isEmpty else { return "\(sign)\(whole)" }
        return "\(sign)\(whole).\(digits)"
    }

    public static func < (lhs: ExactQuantity, rhs: ExactQuantity) -> Bool {
        (try? compare(lhs, rhs)) == .orderedAscending
    }

    public static func add(_ lhs: ExactQuantity, _ rhs: ExactQuantity, context: String) throws -> ExactQuantity {
        let lhsScaled = try CheckedMath.multiply(lhs.numerator, rhs.denominator, context: context)
        let rhsScaled = try CheckedMath.multiply(rhs.numerator, lhs.denominator, context: context)
        let numerator = try CheckedMath.add(lhsScaled, rhsScaled, context: context)
        let denominator = try CheckedMath.multiply(lhs.denominator, rhs.denominator, context: context)
        return try ExactQuantity(numerator: numerator, denominator: denominator)
    }

    public static func subtract(_ lhs: ExactQuantity, _ rhs: ExactQuantity, context: String) throws -> ExactQuantity {
        let lhsScaled = try CheckedMath.multiply(lhs.numerator, rhs.denominator, context: context)
        let rhsScaled = try CheckedMath.multiply(rhs.numerator, lhs.denominator, context: context)
        let numerator = try CheckedMath.subtract(lhsScaled, rhsScaled, context: context)
        guard numerator >= 0 else {
            throw AppError.validation(.init(code: .quantityExceedsStock, field: "quantity", message: "Out quantity exceeds current stock."))
        }
        let denominator = try CheckedMath.multiply(lhs.denominator, rhs.denominator, context: context)
        return try ExactQuantity(numerator: numerator, denominator: denominator)
    }

    public static func compare(_ lhs: ExactQuantity, _ rhs: ExactQuantity) throws -> ComparisonResult {
        let lhsScaled = try CheckedMath.multiply(lhs.numerator, rhs.denominator, context: "comparing exact quantities")
        let rhsScaled = try CheckedMath.multiply(rhs.numerator, lhs.denominator, context: "comparing exact quantities")
        if lhsScaled < rhsScaled { return .orderedAscending }
        if lhsScaled > rhsScaled { return .orderedDescending }
        return .orderedSame
    }

    public func multiplied(byUnitCostPaise unitCostPaise: Int64, context: String) throws -> Int64 {
        let scaled = try CheckedMath.multiply(numerator, unitCostPaise, context: context)
        guard scaled % denominator == 0 else {
            throw AppError.businessRule("Unrepresentable paise result while \(context).")
        }
        return scaled / denominator
    }

    public static func signedAdd(_ lhs: SignedExactQuantity, _ rhs: SignedExactQuantity, context: String) throws -> SignedExactQuantity {
        if lhs.isZero { return rhs }
        if rhs.isZero { return lhs }
        let commonDenominator = try CheckedMath.multiply(lhs.magnitude.denominator, rhs.magnitude.denominator, context: context)
        let lhsScaledMagnitude = try CheckedMath.multiply(lhs.magnitude.numerator, rhs.magnitude.denominator, context: context)
        let rhsScaledMagnitude = try CheckedMath.multiply(rhs.magnitude.numerator, lhs.magnitude.denominator, context: context)
        let lhsSigned = lhs.numerator >= 0 ? lhsScaledMagnitude : try CheckedMath.multiply(lhsScaledMagnitude, -1, context: context)
        let rhsSigned = rhs.numerator >= 0 ? rhsScaledMagnitude : try CheckedMath.multiply(rhsScaledMagnitude, -1, context: context)
        let numerator = try CheckedMath.add(lhsSigned, rhsSigned, context: context)
        if numerator == 0 { return SignedExactQuantity.zero }
        return try SignedExactQuantity(numerator: numerator, denominator: commonDenominator)
    }

    static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if lhs == 0 { return max(1, rhs) }
        var a = lhs
        var b = rhs
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return max(1, a)
    }

    static func absInt64(_ value: Int64) -> Int64 {
        if value == Int64.min { return Int64.max }
        return Swift.abs(value)
    }

    private static func pow10(_ exponent: Int) throws -> Int64 {
        var result: Int64 = 1
        if exponent == 0 { return result }
        for _ in 0..<exponent {
            result = try CheckedMath.multiply(result, 10, context: "building quantity decimal scale")
        }
        return result
    }
}

public struct SignedExactQuantity: Hashable, Sendable, Codable {
    public let numerator: Int64
    public let denominator: Int64

    public init(numerator: Int64, denominator: Int64) throws {
        guard denominator != 0 else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Quantity denominator cannot be zero."))
        }
        guard denominator > 0 else {
            throw AppError.validation(.init(code: .internal, field: "quantity", message: "Quantity denominator must be positive."))
        }
        if numerator == 0 {
            self.numerator = 0
            self.denominator = 1
            return
        }
        let divisor = ExactQuantity.gcd(ExactQuantity.absInt64(numerator), denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    public init(sign: Sign, magnitude: ExactQuantity) throws {
        let signedNumerator = sign == .positive ? magnitude.numerator : try CheckedMath.multiply(magnitude.numerator, -1, context: "creating signed quantity")
        try self.init(numerator: signedNumerator, denominator: magnitude.denominator)
    }

    public enum Sign: String, Sendable, Codable {
        case positive
        case negative
    }

    public static let zero = try! SignedExactQuantity(numerator: 0, denominator: 1)

    public var isZero: Bool { numerator == 0 }

    public var sign: Sign { numerator < 0 ? .negative : .positive }

    public var magnitude: ExactQuantity {
        if numerator == 0 { return try! ExactQuantity.whole(0) }
        return try! ExactQuantity(numerator: ExactQuantity.absInt64(numerator), denominator: denominator)
    }

    public func signedDisplayString() -> String {
        if isZero { return "0" }
        let prefix = numerator < 0 ? "-" : ""
        return prefix + magnitude.displayString
    }
}

public struct AlternateUnitDefinition: Hashable, Sendable, Codable {
    public let alternateUnit: String
    public let baseUnitsPerAlternateUnit: ExactQuantity

    public init(alternateUnit: String, baseUnitsPerAlternateUnit: ExactQuantity) throws {
        let trimmed = alternateUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "alternateUnit", message: "Alternate unit is required."))
        }
        self.alternateUnit = trimmed
        self.baseUnitsPerAlternateUnit = baseUnitsPerAlternateUnit
    }

    public func convertToBaseUnits(_ quantity: ExactQuantity) throws -> ExactQuantity {
        let numerator = try CheckedMath.multiply(quantity.numerator, baseUnitsPerAlternateUnit.numerator, context: "converting alternate quantity to base units")
        let denominator = try CheckedMath.multiply(quantity.denominator, baseUnitsPerAlternateUnit.denominator, context: "converting alternate quantity to base units")
        return try ExactQuantity(numerator: numerator, denominator: denominator)
    }
}
