import XCTest
@testable import Avelo

/// AVL-P2-012 (narration recall, Ctrl+R): recentNarrations previously had
/// no coverage.
final class VoucherRepositoryTests: XCTestCase {

    func testRecentNarrationsReturnsDistinctNonEmptyNarrationsMostRecentFirst() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        func post(_ narration: String, on dateString: String) throws {
            _ = try svc.post(draft: tc.draft(on: dateString, narration: narration, lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 1000, .credit)
            ]), in: tc.fy)
        }
        try post("Opening stock purchase", on: "2024-06-01")
        try post("", on: "2024-06-02")
        try post("Opening stock purchase", on: "2024-06-03") // duplicate narration, later date
        try post("Monthly rent", on: "2024-06-05")

        let narrations = try VoucherRepository(db: tc.db).recentNarrations(companyId: tc.companyId)

        XCTAssertEqual(narrations, ["Monthly rent", "Opening stock purchase"])
    }

    func testRecentNarrationsIsScopedToCompany() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.make()
        _ = try VoucherService(db: other.db, companyId: other.companyId).post(draft: other.draft(on: "2024-06-01", narration: "Other co narration", lines: [
            other.line(other.cashId, 1000, .debit),
            other.line(other.salesId, 1000, .credit)
        ]), in: other.fy)

        let narrations = try VoucherRepository(db: tc.db).recentNarrations(companyId: tc.companyId)

        XCTAssertTrue(narrations.isEmpty)
    }

    func testRecentNarrationsRespectsLimit() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        for i in 0..<5 {
            _ = try svc.post(draft: tc.draft(on: "2024-06-0\(i + 1)", narration: "Narration \(i)", lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 1000, .credit)
            ]), in: tc.fy)
        }

        let narrations = try VoucherRepository(db: tc.db).recentNarrations(companyId: tc.companyId, limit: 2)

        XCTAssertEqual(narrations.count, 2)
    }
}
