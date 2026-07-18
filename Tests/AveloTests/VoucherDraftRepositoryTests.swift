import XCTest
@testable import Avelo

/// AVL-P0-018: autosaved voucher drafts must round-trip exactly, never block
/// on a missing draft, and never leak across companies.
final class VoucherDraftRepositoryTests: XCTestCase {

    private func makeDraft(companyId: Company.ID, id: UUID = UUID(), updatedAt: Date = Date(), accountLedgerId: Account.ID? = nil) -> VoucherEntryDraft {
        VoucherEntryDraft(
            id: id,
            companyId: companyId,
            voucherTypeCode: .payment,
            date: DateFormatters.parseDate("2024-05-01")!,
            partyAccountId: UUID(),
            narration: "Draft narration",
            billReferenceType: .agstRef,
            billReferenceNumber: "REF-1",
            chequeNumber: "CHQ-1",
            chequeDueDate: DateFormatters.parseDate("2024-05-10"),
            accountLedgerId: accountLedgerId,
            linesJSON: #"[{"accountId":null,"amount":"100.00","side":"debit","taxCode":null,"costCenter":null}]"#,
            updatedAt: updatedAt
        )
    }

    func testUpsertThenFindRoundTripsAllFields() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let draft = makeDraft(companyId: tc.companyId)

        try repo.upsert(draft)
        let found = try repo.mostRecent(companyId: tc.companyId)

        XCTAssertEqual(found?.id, draft.id)
        XCTAssertEqual(found?.voucherTypeCode, .payment)
        XCTAssertEqual(found?.narration, "Draft narration")
        XCTAssertEqual(found?.billReferenceType, .agstRef)
        XCTAssertEqual(found?.billReferenceNumber, "REF-1")
        XCTAssertEqual(found?.chequeNumber, "CHQ-1")
        XCTAssertNotNil(found?.chequeDueDate)
        XCTAssertEqual(found?.linesJSON, draft.linesJSON)
    }

    /// AVL-P0-018 follow-up: single-entry-mode drafts (Contra/Payment/Receipt)
    /// must round-trip their cash/bank ledger too, or crash recovery loses
    /// the account and forces the user to re-pick it.
    func testUpsertThenFindRoundTripsAccountLedgerId() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let ledgerId = UUID()
        let draft = makeDraft(companyId: tc.companyId, accountLedgerId: ledgerId)

        try repo.upsert(draft)
        let found = try repo.mostRecent(companyId: tc.companyId)

        XCTAssertEqual(found?.accountLedgerId, ledgerId)
    }

    func testUpsertThenFindRoundTripsNilAccountLedgerId() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let draft = makeDraft(companyId: tc.companyId, accountLedgerId: nil)

        try repo.upsert(draft)
        let found = try repo.mostRecent(companyId: tc.companyId)

        XCTAssertNil(found?.accountLedgerId)
    }

    func testUpsertThenFindRoundTripsItemInvoiceDraftFields() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let ledgerId = UUID()
        let itemId = UUID()
        let draft = VoucherEntryDraft(
            companyId: tc.companyId,
            voucherTypeCode: .sales,
            entryMode: .itemInvoice,
            date: DateFormatters.parseDate("2024-05-01")!,
            partyAccountId: tc.customerId,
            narration: "Item recovery",
            salesPurchaseLedgerId: ledgerId,
            linesJSON: "[]",
            itemLinesJSON: #"[{"itemId":"\#(itemId.uuidString)","quantity":"2","rate":"125.50"}]"#
        )

        try repo.upsert(draft)
        let found = try repo.mostRecent(companyId: tc.companyId)

        XCTAssertEqual(found?.entryMode, .itemInvoice)
        XCTAssertEqual(found?.salesPurchaseLedgerId, ledgerId)
        XCTAssertEqual(found?.itemLinesJSON, draft.itemLinesJSON)
    }

    func testUpsertingSameIdReplacesRatherThanDuplicates() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let id = UUID()
        try repo.upsert(makeDraft(companyId: tc.companyId, id: id, updatedAt: Date()))
        var second = makeDraft(companyId: tc.companyId, id: id, updatedAt: Date().addingTimeInterval(5))
        second.narration = "Updated narration"
        try repo.upsert(second)

        let found = try repo.mostRecent(companyId: tc.companyId)
        XCTAssertEqual(found?.narration, "Updated narration")

        let count: Int64? = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_voucher_drafts WHERE company_id = ?", bind: [.text(tc.companyId.uuidString)]) { $0.int(0) }
        XCTAssertEqual(count, 1)
    }

    func testMostRecentPicksLatestUpdatedAtAmongMultipleDrafts() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let older = makeDraft(companyId: tc.companyId, updatedAt: Date().addingTimeInterval(-60))
        let newer = makeDraft(companyId: tc.companyId, updatedAt: Date())
        try repo.upsert(older)
        try repo.upsert(newer)

        let found = try repo.mostRecent(companyId: tc.companyId)
        XCTAssertEqual(found?.id, newer.id)
    }

    func testMostRecentReturnsNilWhenNoDraftExists() throws {
        let tc = try TestCompany.make()
        let found = try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId)
        XCTAssertNil(found)
    }

    func testDeleteRemovesOnlyTheTargetedDraft() throws {
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        let a = makeDraft(companyId: tc.companyId, updatedAt: Date().addingTimeInterval(-10))
        let b = makeDraft(companyId: tc.companyId, updatedAt: Date())
        try repo.upsert(a)
        try repo.upsert(b)

        try repo.delete(id: b.id)

        let found = try repo.mostRecent(companyId: tc.companyId)
        XCTAssertEqual(found?.id, a.id)
    }

    func testDeleteAllClearsEveryLeftoverDraft() throws {
        // Companies are physically isolated one-per-SQLite-file (R-12), so
        // there is only ever one company's drafts in a given database; this
        // proves "Discard" leaves no leftover row behind when more than one
        // abandoned draft has accumulated across sessions.
        let tc = try TestCompany.make()
        let repo = VoucherDraftRepository(db: tc.db)
        try repo.upsert(makeDraft(companyId: tc.companyId, updatedAt: Date().addingTimeInterval(-10)))
        try repo.upsert(makeDraft(companyId: tc.companyId, updatedAt: Date()))

        try repo.deleteAll(companyId: tc.companyId)

        XCTAssertNil(try repo.mostRecent(companyId: tc.companyId))
        let count: Int64? = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_voucher_drafts") { $0.int(0) }
        XCTAssertEqual(count, 0)
    }
}
