import XCTest
@testable import Avelo

final class VoucherDraftTests: XCTestCase {

    private func line(_ amount: Int64, _ side: EntrySide, account: Account.ID? = UUID()) -> VoucherDraft.Line {
        VoucherDraft.Line(accountId: account, amountPaise: amount, side: side)
    }

    private func draft(_ lines: [VoucherDraft.Line]) -> VoucherDraft {
        VoucherDraft(mode: .create, voucherTypeCode: .journal, date: Date(), lines: lines)
    }

    func testTotalsAndDifference() {
        let d = draft([line(50000, .debit), line(30000, .credit), line(20000, .credit)])
        XCTAssertEqual(d.totalDebitPaise, 50000)
        XCTAssertEqual(d.totalCreditPaise, 50000)
        XCTAssertEqual(d.differencePaise, 0)
        XCTAssertTrue(d.isBalanced)
    }

    func testUnbalancedDraft() {
        let d = draft([line(50000, .debit), line(40000, .credit)])
        XCTAssertEqual(d.differencePaise, 10000) // debit-heavy
        XCTAssertFalse(d.isBalanced)
    }

    func testFilledLinesExcludesEmptyAndZero() {
        let d = draft([
            line(50000, .debit),
            line(0, .credit),                 // zero amount -> excluded
            line(50000, .credit, account: nil) // no account -> excluded
        ])
        XCTAssertEqual(d.filledLines.count, 1)
        XCTAssertEqual(d.filledLines.first?.amountPaise, 50000)
    }

    func testModeOriginalVoucherId() {
        let id = UUID()
        let editDraft = VoucherDraft(mode: .edit(originalVoucherId: id), voucherTypeCode: .journal, date: Date())
        XCTAssertEqual(editDraft.mode.originalVoucherId, id)
        XCTAssertNil(VoucherDraft.Mode.create.originalVoucherId)
    }

    func testBillReferenceFieldsRoundTrip() {
        let draft = VoucherDraft(
            mode: .create,
            voucherTypeCode: .sales,
            date: Date(),
            partyAccountId: UUID(),
            billReferenceType: .agstRef,
            billReferenceNumber: "REF-123",
            narration: "Bill-wise"
        )
        XCTAssertEqual(draft.billReferenceType, .agstRef)
        XCTAssertEqual(draft.billReferenceNumber, "REF-123")
    }

    @MainActor
    func testPasteTsvParsesVoucherLines() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        vm.pasteTSV("Cash\tDr\t100.00\nSales\tCr\t100.00")
        XCTAssertEqual(vm.lines.count, 2)
        XCTAssertEqual(vm.lines[0].amount, "100.00")
        XCTAssertEqual(vm.lines[1].side, .credit)
    }
}
