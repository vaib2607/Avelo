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
        guard let normalized = normalizedDecimalLiteral(filtered), isWellFormedDecimalLiteral(normalized) else { return nil }
        guard let decimal = Decimal(string: normalized) else { return nil }
        return try? rupeesToPaise(decimal)
    }

    /// Resolves `.`/`,` into a single canonical `123456.78`-style literal
    /// (`.` as the decimal point) so both Indian-typed amounts
    /// (`1,18,000.00`) and comma-decimal paste sources (`1.234,56`,
    /// `1234,50`) round-trip correctly, without ever guessing on a shape
    /// that is genuinely ambiguous. Ambiguous or malformed shapes return
    /// `nil` so the caller fails closed instead of silently mis-scaling
    /// the amount.
    private static func normalizedDecimalLiteral(_ filtered: String) -> String? {
        let dotCount = filtered.filter { $0 == "." }.count
        let commaCount = filtered.filter { $0 == "," }.count

        if dotCount == 0 && commaCount == 0 {
            return filtered
        }

        if dotCount > 0 && commaCount > 0 {
            // Both separators present: whichever appears last is the decimal
            // point (`1,18,000.00` vs the European `1.18.000,00`); every
            // instance of the other character is thousands grouping.
            guard let lastDot = filtered.lastIndex(of: "."),
                  let lastComma = filtered.lastIndex(of: ",") else { return nil }
            let decimalIsDot = lastDot > lastComma
            let decimalChar: Character = decimalIsDot ? "." : ","
            let groupChar: Character = decimalIsDot ? "," : "."
            guard filtered.filter({ $0 == decimalChar }).count == 1 else { return nil }
            let stripped = String(filtered.filter { $0 != groupChar })
            return decimalIsDot ? stripped : stripped.replacingOccurrences(of: ",", with: ".")
        }

        let separator: Character = dotCount > 0 ? "." : ","
        let separatorCount = dotCount > 0 ? dotCount : commaCount

        if separatorCount > 1 {
            // Repeated separators only make sense as thousands grouping, and
            // Avelo's own formatting never groups with `.`, so only a
            // repeated `,` is accepted (`1,18,000`); repeated `.` is
            // malformed rather than a grouping style to guess at.
            guard separator == "," else { return nil }
            return String(filtered.filter { $0 != "," })
        }

        // Exactly one separator. Whether it is the decimal point or a
        // thousands group depends on how many digits follow it: two (or
        // one) digits reads as a decimal amount (paise has at most two
        // digits); exactly three reads as a `,`-style thousands group.
        // `.` is never a grouping character in Avelo's own formatting, so a
        // lone `.` is always the decimal point.
        guard let idx = filtered.firstIndex(of: separator) else { return nil }
        let digitsAfter = filtered.distance(from: filtered.index(after: idx), to: filtered.endIndex)
        switch (separator, digitsAfter) {
        case (",", 3):
            return String(filtered.filter { $0 != "," })
        case (",", 1), (",", 2):
            return filtered.replacingOccurrences(of: ",", with: ".")
        case (".", 1), (".", 2):
            return filtered
        default:
            return nil
        }
    }

    /// Final shape guard before handing the literal to `Decimal(string:)`,
    /// which otherwise parses a valid leading prefix of a malformed string
    /// (e.g. `"12.34.56"` -> `12.34`) instead of rejecting it.
    private static func isWellFormedDecimalLiteral(_ s: String) -> Bool {
        guard !s.isEmpty, !s.hasSuffix(".") else { return false }
        var seenDot = false
        for ch in s {
            if ch == "." {
                if seenDot { return false }
                seenDot = true
            } else if !ch.isASCII || !ch.isNumber {
                return false
            }
        }
        return true
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
