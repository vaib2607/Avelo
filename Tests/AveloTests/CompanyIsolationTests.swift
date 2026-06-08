import XCTest
@testable import Avelo

final class CompanyIsolationTests: XCTestCase {

    func testVoucherListIsScopedToCompany() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")

        let serviceA = VoucherService(db: db, companyId: companyA.companyId)
        let serviceB = VoucherService(db: db, companyId: companyB.companyId)

        let voucherA = try serviceA.post(draft: companyA.draft(on: "2024-06-01", lines: [
            companyA.line(companyA.cashId, 50000, .debit),
            companyA.line(companyA.salesId, 50000, .credit)
        ]), in: companyA.fy)

        _ = try serviceB.post(draft: companyB.draft(on: "2024-06-01", lines: [
            companyB.line(companyB.cashId, 70000, .debit),
            companyB.line(companyB.salesId, 70000, .credit)
        ]), in: companyB.fy)

        let listedByA = try serviceA.list(filter: .init(companyId: companyA.companyId))
        XCTAssertEqual(listedByA.map(\.id), [voucherA.voucher.id])
    }

    func testVoucherPostRejectsForeignCompanyAccount() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "A Co")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "B Co")
        let serviceA = VoucherService(db: db, companyId: companyA.companyId)

        XCTAssertThrowsError(try serviceA.post(draft: companyA.draft(on: "2024-06-01", lines: [
            companyA.line(companyA.cashId, 50000, .debit),
            companyA.line(companyB.salesId, 50000, .credit)
        ]), in: companyA.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
        }
    }
}
