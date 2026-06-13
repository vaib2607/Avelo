import Foundation

public enum Currency {

    public static let paisePerRupee: Int64 = 100

    public static func rupeesToPaise(_ rupees: Decimal) -> Int64 {
        var value = rupees * Decimal(paisePerRupee)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
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
        let abs: Int64
        if paise < 0 {
            sign = "-"
            abs = -paise
        } else {
            sign = ""
            abs = paise
        }
        let rupees = abs / paisePerRupee
        let p = abs % paisePerRupee
        let rupeesStr = formatIndianGrouping(rupees)
        let paiseStr = String(format: "%02d", p)
        let body = "₹\(rupeesStr).\(paiseStr)"
        switch style {
        case .indianGrouping:       return "\(sign)\(body)"
        case .plain:                return "\(sign)\(rupees).\(paiseStr)"
        case .signedIndianGrouping: return paise == 0 ? body : "\(sign)\(body)"
        }
    }

    private static func formatIndianGrouping(_ value: Int64) -> String {
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
        return rupeesToPaise(decimal)
    }

    public static func percentagePaise(_ amountPaise: Int64, ratePercent: Int64) -> Int64 {
        let scaled = amountPaise * ratePercent
        if scaled >= 0 {
            return (scaled + 50) / 100
        } else {
            return (scaled - 50) / 100
        }
    }

    public static func formatAmountInput(paise: Int64) -> String {
        if paise == 0 { return "0.00" }
        return formatPaise(paise, style: .plain)
    }
}
