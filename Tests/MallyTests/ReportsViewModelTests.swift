import XCTest
@testable import Mally

@MainActor
final class ReportsViewModelTests: XCTestCase {

    func testLedgerSelectionLoadsRequestedAccountLedger() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.ledgerAccountId = tc.cashId
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.reload()

        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)
        XCTAssertEqual(vm.ledger?.accountName, "Cash")
        XCTAssertEqual(vm.ledger?.rows.count, 1)
        XCTAssertEqual(vm.ledger?.rows.first?.voucherId, try XCTUnwrap(vm.ledger?.rows.first?.voucherId))
    }

    func testLedgerSelectionWithoutAccountClearsLedgerResult() throws {
        let tc = try TestCompany.make()
        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)

        vm.selection = .ledger
        vm.ledgerAccountId = nil
        vm.reload()

        XCTAssertNil(vm.ledger)
        XCTAssertNil(vm.error)
    }

    func testLedgerSelectionReloadsWhenAccountChanges() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)
        _ = try service.post(draft: tc.draft(on: "2024-06-15", lines: [
            tc.line(tc.rentId, 7000, .debit),
            tc.line(tc.cashId, 7000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.ledgerAccountId = tc.cashId
        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)
        XCTAssertEqual(vm.ledger?.rows.count, 2)

        vm.ledgerAccountId = tc.rentId
        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.rentId)
        XCTAssertEqual(vm.ledger?.rows.count, 1)
    }

    func testLedgerSelectionClearRemovesLoadedLedger() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try service.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)

        let vm = ReportsViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.selection = .ledger
        vm.ledgerAccountId = tc.cashId
        vm.fromDate = DateFormatters.parseDate("2024-04-01")!
        vm.toDate = DateFormatters.parseDate("2024-06-30")!

        vm.reload()
        XCTAssertEqual(vm.ledger?.accountId, tc.cashId)

        vm.ledgerAccountId = nil
        vm.reload()

        XCTAssertNil(vm.ledger)
        XCTAssertNil(vm.error)
    }

    func testReportDrillDownRoutesToEditVoucherSheet() {
        let router = AppRouter()
        let voucherId = UUID()

        ReportsNavigation.openVoucher(voucherId, router: router)

        guard case .editVoucher(let routedId) = router.presentedSheet else {
            return XCTFail("Expected edit voucher sheet to be presented")
        }
        XCTAssertEqual(routedId, voucherId)
    }
}
