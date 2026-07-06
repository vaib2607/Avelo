import Foundation

public enum Currency {

    public static let paisePerRupee: Int64 = 100

    public static func rupeesToPaise(_ rupees: Decimal) throws -> Int64 {
        var value = rupees * Decimal(paisePerRupee)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else {
            throw AppError.businessRule("Invalid amount.")
        }
        let decimalValue = number.decimalValue
        let min = Decimal(Int64.min)
        let max = Decimal(Int64.max)
        guard decimalValue >= min, decimalValue <= max else {
            throw AppError.businessRule("Arithmetic overflow while converting rupees to paise.")
        }
        return number.int64Value
    }

    public static func paiseToRupees(_ paise: Int64) -> Decimal {
        Decimal(paise) / Decimal(paisePerRupee)
    }

    public enum FormatStyle: Sendable {
        case indianGrouping
        case plain
        case signedIndianGrouping
    }

    public static func formatPaise(_ paise: Int64, style: FormatStyle = .indianGrouping) -> String {
        let sign: String
        let absPaise: UInt64
        if paise < 0 {
            sign = "-"
            absPaise = paise.magnitude
        } else {
            sign = ""
            absPaise = UInt64(paise)
        }
        let rupees = absPaise / UInt64(paisePerRupee)
        let p = absPaise % UInt64(paisePerRupee)
        let rupeesStr = formatIndianGrouping(rupees)
        let paiseStr = String(format: "%02d", p)
        let body = "₹\(rupeesStr).\(paiseStr)"
        switch style {
        case .indianGrouping:       return "\(sign)\(body)"
        case .plain:                return "\(sign)\(rupees).\(paiseStr)"
        case .signedIndianGrouping: return paise == 0 ? body : "\(sign)\(body)"
        }
    }

    public static func formatAbsolutePaise(_ paise: Int64, style: FormatStyle = .indianGrouping) -> String {
        let absPaise = paise.magnitude
        let rupees = absPaise / UInt64(paisePerRupee)
        let p = absPaise % UInt64(paisePerRupee)
        let rupeesStr = formatIndianGrouping(rupees)
        let paiseStr = String(format: "%02d", p)
        switch style {
        case .indianGrouping, .signedIndianGrouping:
            return "₹\(rupeesStr).\(paiseStr)"
        case .plain:
            return "\(rupees).\(paiseStr)"
        }
    }

    private static func formatIndianGrouping(_ value: UInt64) -> String {
        let s = String(value)
        if s.count <= 3 { return s }
        let last3 = String(s.suffix(3))
        let rest = String(s.dropLast(3))
        var withCommas = ""
        let chars = Array(rest)
        for (i, c) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 2 == 0 {
                withCommas.append(",")
            }
            withCommas.append(c)
        }
        return "\(withCommas),\(last3)"
    }

    public static func parseRupeeInput(_ userTyped: String) -> Int64? {
        let trimmed = userTyped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        if filtered.isEmpty { return nil }
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        guard let decimal = Decimal(string: normalized) else { return nil }
        return try? rupeesToPaise(decimal)
    }

    public static func percentagePaise(_ amountPaise: Int64, ratePercent: Int64) throws -> Int64 {
        let scaled = try CheckedMath.multiply(amountPaise, ratePercent, context: "calculating percentage paise")
        if scaled >= 0 {
            let adjusted = try CheckedMath.add(scaled, 50, context: "rounding percentage paise")
            return adjusted / 100
        } else {
            let adjusted = try CheckedMath.subtract(scaled, 50, context: "rounding percentage paise")
            return adjusted / 100
        }
    }

    public static func formatAmountInput(paise: Int64) -> String {
        if paise == 0 { return "0.00" }
        return formatPaise(paise, style: .plain)
    }
}
