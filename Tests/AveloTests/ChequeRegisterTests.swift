import XCTest
@testable import Avelo

/// AVL-P0-004 (cheque lifecycle UI): `bounceCheque`/`representCheque` were
/// already tested, but the register query that lists cheques for the UI
/// (join to voucher number/party/amount) had zero coverage.
final class ChequeRegisterTests: XCTestCase {

    private func postWithCheque(_ tc: TestCompany, number: String, status: ChequeStatus = .issued) throws -> Voucher {
        try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .payment,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.supplierId,
                narration: "Cheque payment",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 25_000, side: .credit),
                    .init(accountId: tc.supplierId, amountPaise: 25_000, side: .debit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: number,
                chequeDueDate: DateFormatters.parseDate("2024-06-10")!,
                chequeStatus: status
            )
        ).voucher
    }

    func testListChequesJoinsVoucherNumberPartyAndAmount() throws {
        let tc = try TestCompany.make()
        let voucher = try postWithCheque(tc, number: "CHQ-101")

        let rows = try AccountingWorkflowsRepository(db: tc.db).listCheques(companyId: tc.companyId)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cheque.chequeNumber, "CHQ-101")
        XCTAssertEqual(rows[0].voucherNumber, voucher.number)
        XCTAssertEqual(rows[0].amountPaise, 25_000)
        XCTAssertEqual(rows[0].partyName, "Test Supplier")
    }

    func testListChequesFiltersByStatus() throws {
        let tc = try TestCompany.make()
        _ = try postWithCheque(tc, number: "CHQ-201", status: .issued)
        _ = try postWithCheque(tc, number: "CHQ-202", status: .cleared)

        let repo = AccountingWorkflowsRepository(db: tc.db)
        XCTAssertEqual(try repo.listCheques(companyId: tc.companyId, status: .issued).count, 1)
        XCTAssertEqual(try repo.listCheques(companyId: tc.companyId, status: .cleared).count, 1)
        XCTAssertEqual(try repo.listCheques(companyId: tc.companyId).count, 2)
    }

    func testListChequesIsScopedToCompany() throws {
        let tc = try TestCompany.make()
        let other = try TestCompany.make()
        _ = try postWithCheque(tc, number: "CHQ-301")
        _ = try postWithCheque(other, number: "CHQ-302")

        let rows = try AccountingWorkflowsRepository(db: tc.db).listCheques(companyId: tc.companyId)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cheque.chequeNumber, "CHQ-301")
    }

    func testListChequesReflectsBounceStatus() throws {
        let tc = try TestCompany.make()
        let voucher = try postWithCheque(tc, number: "CHQ-401", status: .deposited)
        _ = try VoucherService(db: tc.db, companyId: tc.companyId).bounceCheque(voucher.id, reason: "NSF")

        let rows = try AccountingWorkflowsRepository(db: tc.db).listCheques(companyId: tc.companyId, status: .bounced)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cheque.chequeNumber, "CHQ-401")
    }
}
