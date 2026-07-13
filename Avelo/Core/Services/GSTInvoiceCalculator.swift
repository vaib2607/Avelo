import Foundation

/// Pure GST tax-split engine for item-invoice lines. No I/O, no database —
/// everything it needs is passed in, so it's directly unit-testable.
///
/// Tally's rule: compare the company's state to the party's state. Same
/// state = intra-state = CGST + SGST (half the rate each). Different state
/// = inter-state = IGST (the full rate). CESS, where applicable, applies
/// either way and isn't split.
public struct GSTInvoiceCalculator: Sendable {

    public enum SupplyType: Sendable, Equatable {
        case intraState
        case interState
    }

    /// Throws if either side's state can't be determined — Tally requires
    /// both to be known before it will compute tax at all; guessing here
    /// would silently produce the wrong split on a real invoice.
    public static func resolveSupplyType(companyStateCode: String?, partyStateCode: String?) throws -> SupplyType {
        guard let companyStateCode, !companyStateCode.isEmpty else {
            throw AppError.businessRule("Company GST state is not known. Set the company's GSTIN (Settings > Company Info) to compute GST.")
        }
        guard let partyStateCode, !partyStateCode.isEmpty else {
            throw AppError.businessRule("Party GST state is not known. Set the party's GSTIN or state to compute GST.")
        }
        return companyStateCode == partyStateCode ? .intraState : .interState
    }

    public struct LineInput: Sendable {
        public let quantity: Int64
        public let ratePaise: Int64
        public let gstRateBps: Int?
        public let cessRateBps: Int?
        public let taxability: GSTTaxability

        public init(quantity: Int64, ratePaise: Int64, gstRateBps: Int?, cessRateBps: Int?, taxability: GSTTaxability) {
            self.quantity = quantity
            self.ratePaise = ratePaise
            self.gstRateBps = gstRateBps
            self.cessRateBps = cessRateBps
            self.taxability = taxability
        }
    }

    public struct LineResult: Sendable, Equatable {
        public let taxableValuePaise: Int64
        public let cgstPaise: Int64
        public let sgstPaise: Int64
        public let igstPaise: Int64
        public let cessPaise: Int64

        public var totalTaxPaise: Int64 { cgstPaise + sgstPaise + igstPaise + cessPaise }
    }

    public static func computeLine(_ input: LineInput, supplyType: SupplyType) throws -> LineResult {
        let taxableValue = try CheckedMath.multiply(input.quantity, input.ratePaise, context: "calculating item line taxable value")

        guard input.taxability == .taxable else {
            return LineResult(taxableValuePaise: taxableValue, cgstPaise: 0, sgstPaise: 0, igstPaise: 0, cessPaise: 0)
        }

        let cess: Int64
        if let cessBps = input.cessRateBps, cessBps > 0 {
            cess = try Currency.percentagePaiseBps(taxableValue, rateBasisPoints: Int64(cessBps))
        } else {
            cess = 0
        }

        guard let rateBps = input.gstRateBps, rateBps > 0 else {
            return LineResult(taxableValuePaise: taxableValue, cgstPaise: 0, sgstPaise: 0, igstPaise: 0, cessPaise: cess)
        }

        switch supplyType {
        case .interState:
            let igst = try Currency.percentagePaiseBps(taxableValue, rateBasisPoints: Int64(rateBps))
            return LineResult(taxableValuePaise: taxableValue, cgstPaise: 0, sgstPaise: 0, igstPaise: igst, cessPaise: cess)
        case .intraState:
            // Split the total tax in half rather than computing CGST/SGST
            // independently at half the rate — avoids double-rounding drift
            // on odd rates (e.g. 5%: 2.5% + 2.5% would round unpredictably).
            let totalTax = try Currency.percentagePaiseBps(taxableValue, rateBasisPoints: Int64(rateBps))
            let cgst = totalTax / 2
            let sgst = try CheckedMath.subtract(totalTax, cgst, context: "splitting CGST/SGST from total item tax")
            return LineResult(taxableValuePaise: taxableValue, cgstPaise: cgst, sgstPaise: sgst, igstPaise: 0, cessPaise: cess)
        }
    }
}
