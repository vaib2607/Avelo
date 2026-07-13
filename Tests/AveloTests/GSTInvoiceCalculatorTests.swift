import XCTest
@testable import Avelo

final class GSTInvoiceCalculatorTests: XCTestCase {

    private func line(qty: Int64 = 1, ratePaise: Int64, gstRateBps: Int? = 1800, cessRateBps: Int? = nil, taxability: GSTTaxability = .taxable) -> GSTInvoiceCalculator.LineInput {
        .init(quantity: qty, ratePaise: ratePaise, gstRateBps: gstRateBps, cessRateBps: cessRateBps, taxability: taxability)
    }

    // MARK: - Supply type resolution

    func testResolveSupplyTypeSameStateIsIntraState() throws {
        let type = try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: "27", partyStateCode: "27")
        XCTAssertEqual(type, .intraState)
    }

    func testResolveSupplyTypeDifferentStateIsInterState() throws {
        let type = try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: "27", partyStateCode: "29")
        XCTAssertEqual(type, .interState)
    }

    func testResolveSupplyTypeThrowsWhenCompanyStateMissing() {
        XCTAssertThrowsError(try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: nil, partyStateCode: "27")) { error in
            guard case AppError.businessRule(let message) = error else { return XCTFail("Expected businessRule, got \(error)") }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("company"))
        }
    }

    func testResolveSupplyTypeThrowsWhenPartyStateMissing() {
        XCTAssertThrowsError(try GSTInvoiceCalculator.resolveSupplyType(companyStateCode: "27", partyStateCode: nil)) { error in
            guard case AppError.businessRule(let message) = error else { return XCTFail("Expected businessRule, got \(error)") }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("party"))
        }
    }

    // MARK: - Line computation: intra-state (CGST + SGST split)

    func testIntraStateSplitsRateInHalf() throws {
        // 18% of Rs 1000 (100000 paise) = Rs 180 (18000 paise) -> 9000 + 9000.
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000), supplyType: .intraState)
        XCTAssertEqual(result.taxableValuePaise, 100_000)
        XCTAssertEqual(result.cgstPaise, 9_000)
        XCTAssertEqual(result.sgstPaise, 9_000)
        XCTAssertEqual(result.igstPaise, 0)
        XCTAssertEqual(result.totalTaxPaise, 18_000)
    }

    func testIntraStateOddRateSplitAbsorbsRemainderInSGST() throws {
        // 5% of Rs 101 (10100 paise) = 505 paise total tax -> 252 + 253 (no drift).
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 10_100, gstRateBps: 500), supplyType: .intraState)
        XCTAssertEqual(result.cgstPaise, 252)
        XCTAssertEqual(result.sgstPaise, 253)
        XCTAssertEqual(result.cgstPaise + result.sgstPaise, 505)
    }

    // MARK: - Line computation: inter-state (IGST only)

    func testInterStateAppliesFullRateAsIGST() throws {
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000), supplyType: .interState)
        XCTAssertEqual(result.igstPaise, 18_000)
        XCTAssertEqual(result.cgstPaise, 0)
        XCTAssertEqual(result.sgstPaise, 0)
    }

    // MARK: - CESS

    func testCessAppliesOnTopRegardlessOfSupplyType() throws {
        let intra = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000, cessRateBps: 100), supplyType: .intraState)
        let inter = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000, cessRateBps: 100), supplyType: .interState)
        XCTAssertEqual(intra.cessPaise, 1_000)
        XCTAssertEqual(inter.cessPaise, 1_000)
        XCTAssertEqual(intra.totalTaxPaise, 19_000)
        XCTAssertEqual(inter.totalTaxPaise, 19_000)
    }

    // MARK: - Taxability gates

    func testExemptItemHasNoTaxRegardlessOfRate() throws {
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000, cessRateBps: 100, taxability: .exempt), supplyType: .intraState)
        XCTAssertEqual(result.totalTaxPaise, 0)
        XCTAssertEqual(result.taxableValuePaise, 100_000) // the value itself is still reported
    }

    func testNilRatedItemHasNoTax() throws {
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000, taxability: .nilRated), supplyType: .interState)
        XCTAssertEqual(result.totalTaxPaise, 0)
    }

    func testMissingGSTRateProducesZeroTax() throws {
        let result = try GSTInvoiceCalculator.computeLine(line(ratePaise: 100_000, gstRateBps: nil), supplyType: .intraState)
        XCTAssertEqual(result.totalTaxPaise, 0)
        XCTAssertEqual(result.taxableValuePaise, 100_000)
    }

    // MARK: - Quantity multiplication

    func testTaxableValueMultipliesQuantityByRate() throws {
        let result = try GSTInvoiceCalculator.computeLine(line(qty: 5, ratePaise: 20_000), supplyType: .interState)
        XCTAssertEqual(result.taxableValuePaise, 100_000)
    }

    // MARK: - GSTStateCode.code(forGSTIN:)

    func testGSTStateCodeExtractsKnownPrefix() {
        XCTAssertEqual(GSTStateCode.code(forGSTIN: "27AAPFU0939F1ZV"), "27")
    }

    func testGSTStateCodeRejectsUnknownPrefix() {
        XCTAssertNil(GSTStateCode.code(forGSTIN: "50AAPFU0939F1ZV"))
    }

    func testGSTStateCodeRejectsShortString() {
        XCTAssertNil(GSTStateCode.code(forGSTIN: "2"))
    }
}
