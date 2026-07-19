import XCTest
@testable import Avelo

final class VoucherServiceTests: XCTestCase {
    func testPurchaseVoucherAndBatchUseExplicitDualRolePartyProfile() throws {
        let tc = try TestCompany.make()
        try PartyProfileRepository(db: tc.db).upsert(PartyProfile(
            accountId: tc.customerId,
            companyId: tc.companyId,
            usage: .both
        ))
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        func purchaseDraft(_ narration: String) -> VoucherDraft {
            VoucherDraft(
                mode: .create,
                voucherTypeCode: .purchase,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.customerId,
                narration: narration,
                lines: [
                    tc.line(tc.rentId, 10_000, .debit),
                    tc.line(tc.customerId, 10_000, .credit)
                ]
            )
        }

        _ = try service.post(draft: purchaseDraft("Single profile policy"), in: tc.fy)
        let batch = try service.postBatch(
            [purchaseDraft("Batch profile policy")],
            in: tc.fy
        )

        XCTAssertEqual(batch.count, 1)
    }


    private func voucherSequenceValue(_ number: String, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        guard let suffix = number.split(separator: "/").last, let value = Int(suffix) else {
            XCTFail("Expected voucher number suffix in \(number)", file: file, line: line)
            return -1
        }
        return value
    }

    private func movement(_ db: SQLiteDatabase, account: Account.ID) throws -> (dr: Int64, cr: Int64) {
        let r = try db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr
            FROM trn_accounting_compat WHERE account_id = ?
            """,
            bind: [.text(account.uuidString)]
        ) { ($0.int("dr"), $0.int("cr")) }
        return (r?.0 ?? 0, r?.1 ?? 0)
    }

    private func billAllocation(_ db: SQLiteDatabase, for voucherId: Voucher.ID) throws -> (kind: String, reference: String?, amount: Int64)? {
        try db.queryOne(
            """
            SELECT kind, reference_number, allocated_paise
            FROM avelo_bill_allocations
            WHERE voucher_id = ?
            """,
            bind: [.text(voucherId.uuidString)]
        ) { ($0.text("kind"), try? $0.checkedOptionalText("reference_number"), $0.int("allocated_paise")) }
    }

    private func cheque(_ db: SQLiteDatabase, for voucherId: Voucher.ID) throws -> (id: String, number: String, dueDate: String?, status: String, bouncedReversalVoucherId: String?, representedFromChequeId: String?)? {
        try db.queryOne(
            """
            SELECT id, cheque_number, due_date, status, bounced_reversal_voucher_id, represented_from_cheque_id
            FROM avelo_cheques
            WHERE voucher_id = ?
            """,
            bind: [.text(voucherId.uuidString)]
        ) {
            (
                $0.text("id"),
                $0.text("cheque_number"),
                try? $0.checkedOptionalText("due_date"),
                $0.text("status"),
                try? $0.checkedOptionalText("bounced_reversal_voucher_id"),
                try? $0.checkedOptionalText("represented_from_cheque_id")
            )
        }
    }

    func testBalancedPostPersistsWithEqualDebitCredit() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let draft = tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ])
        let result = try svc.post(draft: draft, in: tc.fy)
        XCTAssertEqual(result.voucher.totalPaise, 50000)

        // Whole-book invariant: total debits == total credits.
        let totals = try tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr
            FROM trn_accounting_compat
            """
        ) { ($0.int("dr"), $0.int("cr")) }
        XCTAssertEqual(totals?.0, totals?.1)
    }

    func testLegacyAutoPromptModeDoesNotExposeIncompleteInventoryPrompt() throws {
        let tc = try TestCompany.make()
        try tc.db.execute(
            "UPDATE avelo_companies SET inventory_link_mode = 'autoPrompt' WHERE id = ?",
            [.text(tc.companyId.uuidString)]
        )
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let result = try svc.post(
            draft: tc.draft(type: .sales, on: "2024-06-01", lines: [
                tc.line(tc.cashId, 50000, .debit),
                tc.line(tc.salesId, 50000, .credit)
            ]),
            in: tc.fy
        )

        XCTAssertNil(result.inventoryPrompt)
    }

    func testPostBatchPersistsAllVouchersInOneBalancedBatch() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let drafts = (0..<25).map { i in
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1000 + Int64(i), .debit),
                tc.line(tc.salesId, 1000 + Int64(i), .credit)
            ])
        }

        let results = try svc.postBatch(drafts, in: tc.fy)
        XCTAssertEqual(results.count, 25)

        let totals = try tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr,
                   COUNT(DISTINCT voucher_id) AS c
            FROM trn_accounting_compat
            """
        ) { ($0.int("dr"), $0.int("cr"), $0.int("c")) }
        XCTAssertEqual(totals?.0, totals?.1)
        XCTAssertEqual(totals?.2, 25)
    }

    func testPostBatchMaintainsContinuousAuditChainAcrossChunks() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let drafts = (0..<501).map { i in
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000 + Int64(i), .debit),
                tc.line(tc.salesId, 1_000 + Int64(i), .credit)
            ])
        }

        let results = try svc.postBatch(drafts, in: tc.fy)
        let audit = AuditRepository(db: tc.db)
        let events = try audit.list(filter: .init(companyId: tc.companyId, action: .voucherPosted, limit: 600))

        XCTAssertEqual(results.count, 501)
        XCTAssertEqual(events.count, 501)
        XCTAssertEqual(Set(events.map(\.entityId)), Set(results.map { $0.voucher.id.uuidString }))
        XCTAssertNoThrow(try audit.verifyIntegrity(companyId: tc.companyId))
    }

    func testPostBatchRejectsInactiveAccountsFromTransactionSnapshot() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        try AccountService(db: tc.db, companyId: tc.companyId).disableAccount(tc.salesId)

        XCTAssertThrowsError(try svc.postBatch([
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ])
        ], in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
        }
    }

    func testPostBatchRejectsLockedFinancialYearFromTransactionSnapshot() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try svc.postBatch([
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1_000, .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ])
        ], in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherFYLocked)
        }
    }

    func testPostBatchPreservesSingleEntryCashBankEligibility() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let results = try svc.postBatch([
            tc.draft(type: .payment, on: "2024-06-01", lines: [
                tc.line(tc.salesId, 1_000, .debit),
                tc.line(tc.cashId, 1_000, .credit)
            ])
        ], in: tc.fy)

        XCTAssertEqual(results.count, 1)
    }

    func testPostBatchRollsBackOnlyCurrentChunkOnFailure() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        var drafts = (0..<500).map { i in
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1000 + Int64(i), .debit),
                tc.line(tc.salesId, 1000 + Int64(i), .credit)
            ])
        }
        drafts.append(contentsOf: (0..<499).map { i in
            tc.draft(on: "2024-06-02", lines: [
                tc.line(tc.cashId, 2000 + Int64(i), .debit),
                tc.line(tc.salesId, 2000 + Int64(i), .credit)
            ])
        })
        drafts.append(
            tc.draft(on: "2024-06-03", lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 900, .credit)
            ])
        )
        drafts.append(contentsOf: (0..<200).map { i in
            tc.draft(on: "2024-06-04", lines: [
                tc.line(tc.cashId, 3000 + Int64(i), .debit),
                tc.line(tc.salesId, 3000 + Int64(i), .credit)
            ])
        })
        XCTAssertEqual(drafts.count, 1200)

        XCTAssertThrowsError(try svc.postBatch(drafts, in: tc.fy))

        let voucherCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) } ?? 0
        let lineCount = try tc.db.queryOne("SELECT COUNT(*) FROM trn_accounting_compat") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 500)
        XCTAssertEqual(lineCount, 1000)

        let audit = AuditRepository(db: tc.db)
        let auditEvents = try audit.list(filter: .init(companyId: tc.companyId, action: .voucherPosted, limit: 600))
        XCTAssertEqual(auditEvents.count, 500)
        XCTAssertNoThrow(try audit.verifyIntegrity(companyId: tc.companyId))

        let next = try svc.post(draft: tc.draft(on: "2024-06-05", lines: [
            tc.line(tc.cashId, 4_000, .debit),
            tc.line(tc.salesId, 4_000, .credit)
        ]), in: tc.fy)
        let nextSequence = try tc.db.queryOne(
            "SELECT sequence_number FROM avelo_audit_events WHERE entity_id = ?",
            bind: [.text(next.voucher.id.uuidString)]
        ) { $0.int("sequence_number") }
        XCTAssertEqual(nextSequence, 501)
    }

    func testUnbalancedPostThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let draft = tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 40000, .credit)
        ])
        XCTAssertThrowsError(try svc.post(draft: draft, in: tc.fy)) { error in
            guard case AppError.validation(let ve) = error else {
                return XCTFail("Expected AppError.validation, got \(error)")
            }
            XCTAssertEqual(ve.code, .voucherDebitCreditMismatch)
        }
    }

    func testSalesVoucherAutoAddsDebitRoundOffForSmallGSTRoundingDifference() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.customerId,
                narration: "GST rounded invoice",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 11_799, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208"),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
                ]
            ),
            in: tc.fy
        ).voucher

        XCTAssertEqual(posted.totalPaise, 11_800)
        let lines = try svc.lines(for: posted.id)
        XCTAssertEqual(lines.count, 5)
        let roundOffLine = try XCTUnwrap(lines.first(where: { $0.accountId == tc.roundOffId }))
        XCTAssertEqual(roundOffLine.amountPaise, 1)
        XCTAssertEqual(roundOffLine.side, .debit)
    }

    /// `normalizedDraftForPosting` reconstructs `VoucherDraft` at two sites
    /// inside the GST round-off branch (one before the round-off line is
    /// added, one after) — each must explicitly carry
    /// `duplicatedFromVoucherId` forward or a duplicated voucher's lineage
    /// would silently vanish for exactly the GST-eligible types most likely
    /// to need round-off. This exercises the branch that actually appends a
    /// round-off line (the second, later reconstruction).
    func testDuplicateLineageSurvivesGSTRoundOffNormalization() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let source = try svc.post(
            draft: VoucherDraft(
                mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.customerId, narration: "Source invoice",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 11_799, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208"),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
                ]
            ),
            in: tc.fy
        ).voucher

        let duplicate = try svc.post(
            draft: VoucherDraft(
                mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-02")!,
                partyAccountId: tc.customerId, narration: "Duplicate of source invoice",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 11_799, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208"),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
                ],
                duplicatedFromVoucherId: source.id
            ),
            in: tc.fy
        ).voucher

        // Confirm this actually exercised the round-off-adding branch, not
        // just the early-return path.
        let lines = try svc.lines(for: duplicate.id)
        XCTAssertTrue(lines.contains { $0.accountId == tc.roundOffId })
        XCTAssertEqual(duplicate.duplicatedFromVoucherId, source.id)
    }

    /// Reversing or cancelling a voucher that was itself a duplicate must
    /// not bleed `duplicatedFromVoucherId` into the reversal/cancellation
    /// voucher — those get their own lineage via `reversalOfId`, never a
    /// borrowed "duplicated from" value.
    func testReverseAndCancelOfADuplicateDoNotInheritDuplicateLineage() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let source = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 1_000, .debit), tc.line(tc.salesId, 1_000, .credit)
        ]), in: tc.fy).voucher
        let duplicate = try svc.post(
            draft: VoucherDraft(
                mode: .create, voucherTypeCode: .journal, date: DateFormatters.parseDate("2024-06-02")!,
                narration: "Duplicate", lines: [
                    .init(accountId: tc.cashId, amountPaise: 1_000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 1_000, side: .credit)
                ],
                duplicatedFromVoucherId: source.id
            ),
            in: tc.fy
        ).voucher
        XCTAssertEqual(duplicate.duplicatedFromVoucherId, source.id)

        let reversed = try svc.reverse(duplicate.id, reason: "test reversal")
        XCTAssertEqual(reversed.reversalOfId, duplicate.id)
        XCTAssertNil(reversed.duplicatedFromVoucherId,
                      "A reversal must not inherit the reversed voucher's duplicate lineage")

        // Reload the original duplicate too: reversing it must not rewrite
        // its own lineage field.
        let persistedDuplicate = try XCTUnwrap(svc.findById(duplicate.id))
        XCTAssertEqual(persistedDuplicate.duplicatedFromVoucherId, source.id)
    }

    func testInvoiceEditRecomputesRoundOffDeterministically() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.customerId,
                narration: "Rounded invoice",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 11_801, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208"),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.roundOffId, amountPaise: 99, side: .debit)
                ]
            ),
            in: tc.fy
        ).voucher

        let edited = try svc.edit(
            posted.id,
            with: VoucherDraft(
                mode: .edit(originalVoucherId: posted.id),
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-02")!,
                partyAccountId: tc.customerId,
                narration: "Rounded invoice edited",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 11_798, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208"),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.roundOffId, amountPaise: 77, side: .credit)
                ]
            ),
            in: tc.fy
        )

        XCTAssertEqual(edited.totalPaise, 11_800)
        let lines = try svc.lines(for: edited.id)
        let roundOffLines = lines.filter { $0.accountId == tc.roundOffId }
        XCTAssertEqual(roundOffLines.count, 1)
        XCTAssertEqual(roundOffLines.first?.amountPaise, 2)
        XCTAssertEqual(roundOffLines.first?.side, .debit)
    }

    func testNonGSTVoucherMismatchStillThrowsWithoutRoundOff() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(
            try svc.post(
                draft: VoucherDraft(
                    mode: .create,
                    voucherTypeCode: .sales,
                    date: DateFormatters.parseDate("2024-06-01")!,
                    partyAccountId: tc.customerId,
                    narration: "No GST lines",
                    lines: [
                        .init(accountId: tc.customerId, amountPaise: 10_001, side: .debit),
                        .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit, taxCode: "7208")
                    ]
                ),
                in: tc.fy
            )
        ) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherDebitCreditMismatch)
        }
    }

    func testReverseNetsAccountsToZeroMovement() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        _ = try svc.reverse(posted.voucher.id, reason: "test reversal")

        let cash = try movement(tc.db, account: tc.cashId)
        let sales = try movement(tc.db, account: tc.salesId)
        // After reversal each account's signed movement nets to zero.
        XCTAssertEqual(cash.dr - cash.cr, 0)
        XCTAssertEqual(sales.dr - sales.cr, 0)
    }

    func testPostMarksAccountsUsed() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let repo = AccountRepository(db: tc.db)
        XCTAssertNotNil(try repo.findById(tc.cashId)?.lastUsedAt)
        XCTAssertNotNil(try repo.findById(tc.salesId)?.lastUsedAt)
    }

    func testVoucherNumbersAreUniqueAcrossSequentialPosts() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let first = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy).voucher.number
        let second = try svc.post(draft: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 60000, .debit),
            tc.line(tc.salesId, 60000, .credit)
        ]), in: tc.fy).voucher.number

        XCTAssertNotEqual(first, second)
    }

    func testFailedPostDoesNotConsumeVoucherNumber() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let first = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy).voucher.number

        XCTAssertThrowsError(try svc.post(draft: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 40000, .credit)
        ]), in: tc.fy))

        let second = try svc.post(draft: tc.draft(on: "2024-06-03", lines: [
            tc.line(tc.cashId, 60000, .debit),
            tc.line(tc.salesId, 60000, .credit)
        ]), in: tc.fy).voucher.number

        XCTAssertEqual(try voucherSequenceValue(first), 1)
        XCTAssertEqual(try voucherSequenceValue(second), 2)
    }

    func testFailedBatchChunkDoesNotAdvanceVoucherNumbers() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        var drafts = (0..<500).map { i in
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1000 + Int64(i), .debit),
                tc.line(tc.salesId, 1000 + Int64(i), .credit)
            ])
        }
        drafts.append(contentsOf: (0..<499).map { i in
            tc.draft(on: "2024-06-02", lines: [
                tc.line(tc.cashId, 2000 + Int64(i), .debit),
                tc.line(tc.salesId, 2000 + Int64(i), .credit)
            ])
        })
        drafts.append(
            tc.draft(on: "2024-06-03", lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 900, .credit)
            ])
        )

        XCTAssertThrowsError(try svc.postBatch(drafts, in: tc.fy))

        let next = try svc.post(draft: tc.draft(on: "2024-06-04", lines: [
            tc.line(tc.cashId, 70000, .debit),
            tc.line(tc.salesId, 70000, .credit)
        ]), in: tc.fy).voucher.number

        XCTAssertEqual(try voucherSequenceValue(next), 501)
    }

    func testConcurrentPostsAllocateGapFreeSequentialVoucherNumbers() throws {
        let fixture = try TestCompany.makeOnDisk()
        defer {
            fixture.fixture.db.close()
            try? FileManager.default.removeItem(at: fixture.cleanupURL)
        }

        let dbURL = fixture.cleanupURL.appendingPathComponent("company.sqlite")
        let extraDbs = try (0..<3).map { _ in try SQLiteDatabase(path: dbURL.path) }
        defer { extraDbs.forEach { $0.close() } }

        let services = [VoucherService(db: fixture.fixture.db, companyId: fixture.fixture.companyId)] +
            extraDbs.map { VoucherService(db: $0, companyId: fixture.fixture.companyId) }

        let lock = NSLock()
        var numbers: [String] = []
        var errors: [Error] = []
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "voucher-number-concurrency", attributes: .concurrent)

        for i in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let service = services[i % services.count]
                    let number = try service.post(
                        draft: fixture.fixture.draft(on: "2024-06-01", narration: "Concurrent \(i)", lines: [
                            fixture.fixture.line(fixture.fixture.cashId, 10_000 + Int64(i), .debit),
                            fixture.fixture.line(fixture.fixture.salesId, 10_000 + Int64(i), .credit)
                        ]),
                        in: fixture.fixture.fy
                    ).voucher.number
                    lock.lock()
                    numbers.append(number)
                    lock.unlock()
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
            }
        }

        group.wait()
        XCTAssertTrue(errors.isEmpty, "Concurrent post errors: \(errors)")

        let sequenceValues = try numbers.map { try voucherSequenceValue($0) }.sorted()
        XCTAssertEqual(sequenceValues, Array(1...20))
    }

    func testSeededChartIncludesRoundOffLedger() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyId = UUID()
        try AuditTestKeySupport.ensureKey(for: companyId)
        let timestamp = DateFormatters.formatIsoTimestamp(Date())
        try db.execute(
            "INSERT INTO avelo_companies (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [.text(companyId.uuidString), .text("Seed Test"), .text(timestamp), .text(timestamp)]
        )
        let fyId = UUID()
        let start = DateFormatters.parseDate("2024-04-01")!
        let end = DateFormatters.parseDate("2025-03-31")!
        try db.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [.text(fyId.uuidString), .text(companyId.uuidString), .text("2024-25"), .date(start), .date(end), .date(start), .text(timestamp)]
        )

        try SeedLoader().loadDefaults(
            into: db,
            companyId: companyId,
            financialYearId: fyId
        )

        let roundOff = try AccountRepository(db: db).findByCode("ROUND_OFF", companyId: companyId)
        XCTAssertNotNil(roundOff)
    }

    func testBillWorkflowInputsPersistAndRoundTripThroughLoadDraft() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let debtorsGroup = try AccountService(db: tc.db, companyId: tc.companyId)
            .createGroup(code: "SD", name: "Sundry Debtors", nature: .assets, parentGroupId: try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId)).groupId)
        let debtor = try AccountService(db: tc.db, companyId: tc.companyId)
            .createAccount(.init(code: "DEBTOR_A", name: "Debtor A", groupId: debtorsGroup.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: debtor.id,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Bill workflow test",
                lines: [
                    .init(accountId: debtor.id, amountPaise: 100000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                billAllocationKind: .newRef,
                billAllocationNumber: "INV-77"
            )
        )

        let allocation = try XCTUnwrap(billAllocation(tc.db, for: posted.voucher.id))
        XCTAssertEqual(allocation.kind, BillAllocationKind.newRef.rawValue)
        XCTAssertEqual(allocation.reference, "INV-77")
        XCTAssertEqual(allocation.amount, 100000)

        let loaded = try svc.loadDraft(from: posted.voucher.id)
        XCTAssertEqual(loaded.billReferenceType, .newRef)
        XCTAssertEqual(loaded.billReferenceNumber, "INV-77")
    }

    func testWorkflowInputsRejectDeferredFieldsWithoutPersistingVoucher() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.customerId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Deferred workflow test",
                lines: [
                    .init(accountId: tc.customerId, amountPaise: 118000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100000, side: .credit),
                    .init(accountId: tc.rentId, amountPaise: 18000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                billAllocationKind: .newRef,
                billAllocationNumber: "INV-77",
                chequeNumber: "CHQ-123",
                chequeDueDate: DateFormatters.parseDate("2024-06-15")!,
                tdsSectionCode: "194C",
                tdsTaxPaise: 5000,
                tcsSectionCode: "206C",
                tcsTaxPaise: 3000
            )
        )) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }

        let voucherCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 0)
    }

    func testChequeWorkflowPersistsAndLoadsForEdit() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .payment,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Cheque payment",
                lines: [
                    .init(accountId: tc.rentId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.cashId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-001",
                chequeDueDate: DateFormatters.parseDate("2024-06-15")!,
                chequeStatus: .issued
            )
        )

        let stored = try XCTUnwrap(cheque(tc.db, for: posted.voucher.id))
        XCTAssertEqual(stored.number, "CHQ-001")
        XCTAssertEqual(stored.status, ChequeStatus.issued.rawValue)

        let workflow = try AccountingWorkflowsRepository(db: tc.db).workflowInputs(for: posted.voucher.id)
        XCTAssertEqual(workflow.chequeNumber, "CHQ-001")
        XCTAssertEqual(workflow.chequeStatus, .issued)
        XCTAssertEqual(workflow.chequeDueDate, DateFormatters.parseDate("2024-06-15")!)
    }

    func testEditUpdatesPersistedChequeWorkflow() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .payment,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Editable cheque",
                lines: [
                    .init(accountId: tc.rentId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.cashId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-OLD",
                chequeDueDate: DateFormatters.parseDate("2024-06-10")!,
                chequeStatus: .issued
            )
        )

        _ = try svc.edit(
            posted.voucher.id,
            with: VoucherDraft(
                mode: .edit(originalVoucherId: posted.voucher.id),
                voucherTypeCode: .payment,
                date: DateFormatters.parseDate("2024-06-02")!,
                narration: "Edited cheque",
                lines: [
                    .init(accountId: tc.rentId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.cashId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-NEW",
                chequeDueDate: DateFormatters.parseDate("2024-06-20")!,
                chequeStatus: .deposited
            )
        )

        let stored = try XCTUnwrap(cheque(tc.db, for: posted.voucher.id))
        XCTAssertEqual(stored.number, "CHQ-NEW")
        XCTAssertEqual(stored.status, ChequeStatus.deposited.rawValue)
        XCTAssertEqual(stored.dueDate, "2024-06-20")
    }

    func testEditUpdatesPersistedBillAllocation() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let debtorsGroup = try AccountService(db: tc.db, companyId: tc.companyId)
            .createGroup(code: "SD2", name: "Sundry Debtors 2", nature: .assets, parentGroupId: try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId)).groupId)
        let debtor = try AccountService(db: tc.db, companyId: tc.companyId)
            .createAccount(.init(code: "DEBTOR_B", name: "Debtor B", groupId: debtorsGroup.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: debtor.id,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-OLD",
                narration: "Original bill",
                lines: [
                    .init(accountId: debtor.id, amountPaise: 100000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-OLD")
        )

        _ = try svc.edit(
            posted.voucher.id,
            with: VoucherDraft(
                mode: .edit(originalVoucherId: posted.voucher.id),
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-02")!,
                partyAccountId: debtor.id,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-NEW",
                narration: "Edited bill",
                lines: [
                    .init(accountId: debtor.id, amountPaise: 120000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 120000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-NEW")
        )

        let allocation = try XCTUnwrap(billAllocation(tc.db, for: posted.voucher.id))
        XCTAssertEqual(allocation.kind, BillAllocationKind.newRef.rawValue)
        XCTAssertEqual(allocation.reference, "INV-NEW")
        XCTAssertEqual(allocation.amount, 120000)
    }

    func testEditInLockedFinancialYearThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherFYLocked)
        }
    }

    func testValidateAccumulatesAllInactiveAccountErrors() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let accountService = AccountService(db: tc.db, companyId: tc.companyId)
        let extraGroup = try accountService.createGroup(code: "EXT", name: "Extra", nature: .assets)
        let a1 = try accountService.createAccount(.init(code: "X1", name: "X1", groupId: extraGroup.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let a2 = try accountService.createAccount(.init(code: "X2", name: "X2", groupId: extraGroup.id, openingBalancePaise: 0, openingBalanceSide: .credit, gstin: nil, existingAccountId: nil))
        try accountService.disableAccount(a1.id)
        try accountService.disableAccount(a2.id)

        let draft = tc.draft(on: "2024-06-01", lines: [
            tc.line(a1.id, 1000, .debit),
            tc.line(a2.id, 1000, .credit)
        ])
        let result = try svc.validate(draft: draft, in: tc.fy)
        guard case .invalid(let errors) = result else {
            return XCTFail("Expected invalid result")
        }
        XCTAssertEqual(errors.filter { $0.code == .voucherAccountInactive }.count, 2)
    }

    func testHistoricalEditExplainsNewlyDeactivatedRetainedAccounts() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let accountService = AccountService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try accountService.disableAccount(tc.cashId)
        try accountService.disableAccount(tc.salesId)

        let edited = tc.draft(on: "2024-06-01", narration: "Narration tweak", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ])
        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: edited, in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
            XCTAssertTrue(validation.message.localizedCaseInsensitiveContains("inactive"))
        }
    }

    func testPostInLockedFinancialYearThrows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        XCTAssertThrowsError(try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherFYLocked)
        }
    }

    func testLockedYearVoucherCanReverseIntoLatestOpenYear() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try FinancialYearRepository(db: tc.db).lock(tc.fy.id)

        let nextFY = FinancialYear(
            companyId: tc.companyId,
            label: "2025-26",
            startDate: DateFormatters.parseDate("2025-04-01")!,
            endDate: DateFormatters.parseDate("2026-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2025-04-01")!
        )
        try FinancialYearRepository(db: tc.db).insert(nextFY)

        let reversal = try svc.reverse(posted.voucher.id, reason: "lock correction")
        XCTAssertEqual(reversal.financialYearId, nextFY.id)
        XCTAssertEqual(reversal.reversalOfId, posted.voucher.id)
    }

    func testReverseMirrorsBillAllocationForSettlement() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let debtorsGroup = try AccountService(db: tc.db, companyId: tc.companyId)
            .createGroup(code: "SD3", name: "Sundry Debtors 3", nature: .assets, parentGroupId: try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId)).groupId)
        let debtor = try AccountService(db: tc.db, companyId: tc.companyId)
            .createAccount(.init(code: "DEBTOR_C", name: "Debtor C", groupId: debtorsGroup.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: debtor.id,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-REV",
                narration: "Reversible bill",
                lines: [
                    .init(accountId: debtor.id, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-REV")
        )

        let reversal = try svc.reverse(posted.voucher.id, reason: "test reversal")
        let mirrored = try XCTUnwrap(billAllocation(tc.db, for: reversal.id))
        XCTAssertEqual(mirrored.kind, BillAllocationKind.newRef.rawValue)
        XCTAssertEqual(mirrored.reference, "INV-REV")
        XCTAssertEqual(mirrored.amount, 50000)

        let outstanding = try ReportService(db: tc.db, companyId: tc.companyId).outstanding(
            asOfDate: DateFormatters.parseDate("2025-03-31")!,
            direction: .receivable
        )
        XCTAssertEqual(outstanding.rows.count, 0)
        XCTAssertEqual(outstanding.totalPaise, 0)
    }

    func testBounceChequeCreatesLinkedReversalAndMarksChequeBounced() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Cheque receipt",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-BOUNCE",
                chequeDueDate: DateFormatters.parseDate("2024-06-05")!,
                chequeStatus: .deposited
            )
        )

        let reversal = try svc.bounceCheque(posted.voucher.id, reason: "NSF")
        XCTAssertTrue(reversal.isReversal)
        XCTAssertEqual(reversal.reversalOfId, posted.voucher.id)

        let stored = try XCTUnwrap(cheque(tc.db, for: posted.voucher.id))
        XCTAssertEqual(stored.status, ChequeStatus.bounced.rawValue)
        XCTAssertEqual(stored.bouncedReversalVoucherId, reversal.id.uuidString)
        let bounceEvents = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .chequeBounced)
        )
        XCTAssertEqual(bounceEvents.count, 1)
        XCTAssertNotNil(bounceEvents.first?.snapshotBeforeJson)
        XCTAssertNotNil(bounceEvents.first?.snapshotAfterJson)
        XCTAssertEqual(bounceEvents.first?.reason, "Cheque bounced: NSF [actor=user]")
    }

    func testBounceChequeRollsBackReversalAndChequeWhenAuditFails() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try service.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Rollback cheque",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 10_000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10_000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: .init(chequeNumber: "CHQ-ROLLBACK", chequeStatus: .deposited)
        )
        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_fail_cheque_bounce_audit
            BEFORE INSERT ON avelo_audit_events
            WHEN NEW.action = 'chequeBounced'
            BEGIN SELECT RAISE(ABORT, 'forced cheque audit failure'); END;
            """
        )

        XCTAssertThrowsError(try service.bounceCheque(posted.voucher.id, reason: "NSF"))

        let stored = try XCTUnwrap(cheque(tc.db, for: posted.voucher.id))
        XCTAssertEqual(stored.status, ChequeStatus.deposited.rawValue)
        XCTAssertNil(stored.bouncedReversalVoucherId)
        XCTAssertEqual(
            try tc.db.queryOne(
                "SELECT COUNT(*) FROM avelo_vouchers WHERE reversal_of_id = ?",
                bind: [.text(posted.voucher.id.uuidString)]
            ) { $0.int(0) },
            0
        )
    }

    func testRepresentChequeCreatesFreshVoucherAndLinksToBouncedCheque() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-06-01")!,
                narration: "Representable cheque receipt",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-REP",
                chequeDueDate: DateFormatters.parseDate("2024-06-05")!,
                chequeStatus: .deposited
            )
        )
        _ = try svc.bounceCheque(posted.voucher.id, reason: "return memo")

        let represented = try svc.representCheque(
            posted.voucher.id,
            on: DateFormatters.parseDate("2024-06-10")!,
            reason: "re-presented"
        )

        XCTAssertFalse(represented.isReversal)
        XCTAssertNotEqual(represented.id, posted.voucher.id)
        XCTAssertNotEqual(represented.number, posted.voucher.number)

        let originalCheque = try XCTUnwrap(cheque(tc.db, for: posted.voucher.id))
        let representedCheque = try XCTUnwrap(cheque(tc.db, for: represented.id))
        XCTAssertEqual(representedCheque.number, "CHQ-REP")
        XCTAssertEqual(representedCheque.status, ChequeStatus.issued.rawValue)
        XCTAssertEqual(representedCheque.representedFromChequeId, originalCheque.id)
        XCTAssertEqual(representedCheque.dueDate, "2024-06-05")
        let representedEvents = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .chequeRepresented)
        )
        XCTAssertEqual(representedEvents.count, 1)
        XCTAssertNotNil(representedEvents.first?.snapshotBeforeJson)
        XCTAssertNotNil(representedEvents.first?.snapshotAfterJson)
    }

    func testReverseRejectsDisabledAccountsThroughValidation() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try AccountService(db: tc.db, companyId: tc.companyId).disableAccount(tc.salesId)

        XCTAssertThrowsError(try svc.reverse(posted.voucher.id, reason: "disabled account")) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .voucherAccountInactive)
        }
    }

    func testVoucherCannotBeReversedTwice() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        _ = try svc.reverse(posted.voucher.id, reason: "first")

        XCTAssertThrowsError(try svc.reverse(posted.voucher.id, reason: "second")) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected business rule, got \(error)")
            }
            XCTAssertTrue(message.contains("already been reversed"))
        }
    }

    func testCancelMarksVoucherCancelledAndCreatesLinkedReversal() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let debtorsGroup = try AccountService(db: tc.db, companyId: tc.companyId)
            .createGroup(code: "SD4", name: "Sundry Debtors 4", nature: .assets, parentGroupId: try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId)).groupId)
        let debtor = try AccountService(db: tc.db, companyId: tc.companyId)
            .createAccount(.init(code: "DEBTOR_D", name: "Debtor D", groupId: debtorsGroup.id, openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil, existingAccountId: nil))
        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: debtor.id,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-CANCEL",
                narration: "Cancelable bill",
                lines: [
                    .init(accountId: debtor.id, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-CANCEL")
        )

        let cancelled = try svc.cancel(posted.voucher.id, reason: "duplicate entry", actor: "tester")
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.cancellationReason, "duplicate entry")
        XCTAssertEqual(cancelled.cancelledBy, "tester")
        XCTAssertNotNil(cancelled.cancelledAt)
        XCTAssertNotNil(cancelled.cancellationVoucherId)

        let persisted = try XCTUnwrap(svc.findById(posted.voucher.id))
        XCTAssertEqual(persisted.status, .cancelled)
        XCTAssertEqual(persisted.number, posted.voucher.number)
        XCTAssertEqual(persisted.cancellationVoucherId, cancelled.cancellationVoucherId)

        let reversal = try XCTUnwrap(svc.findById(XCTUnwrap(cancelled.cancellationVoucherId)))
        XCTAssertTrue(reversal.isReversal)
        XCTAssertEqual(reversal.reversalOfId, posted.voucher.id)
        let mirrored = try XCTUnwrap(billAllocation(tc.db, for: reversal.id))
        XCTAssertEqual(mirrored.kind, BillAllocationKind.newRef.rawValue)
        XCTAssertEqual(mirrored.reference, "INV-CANCEL")
        XCTAssertEqual(mirrored.amount, 50000)

        let debtorMovement = try movement(tc.db, account: debtor.id)
        let sales = try movement(tc.db, account: tc.salesId)
        XCTAssertEqual(debtorMovement.dr - debtorMovement.cr, 0)
        XCTAssertEqual(sales.dr - sales.cr, 0)
    }

    func testCancelledVoucherCannotBeEditedOrCancelledAgain() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        _ = try svc.cancel(posted.voucher.id, reason: "void")

        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("cancelled"))
        }

        XCTAssertThrowsError(try svc.cancel(posted.voucher.id, reason: "again")) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("already been cancelled"))
        }
    }

    func testCancelledVoucherNumberIsNotReusedByNextPost() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let first = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)
        _ = try svc.cancel(first.voucher.id, reason: "void")

        let second = try svc.post(draft: tc.draft(on: "2024-06-02", lines: [
            tc.line(tc.cashId, 60000, .debit),
            tc.line(tc.salesId, 60000, .credit)
        ]), in: tc.fy)

        XCTAssertNotEqual(first.voucher.number, second.voucher.number)
    }

    func testVoucherDeleteDoesNotCascadeLedgerLinesSilently() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let beforeDeleteCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM trn_accounting_compat WHERE voucher_id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(beforeDeleteCount, 2)

        XCTAssertThrowsError(try tc.db.execute(
            "DELETE FROM avelo_vouchers WHERE id = ?",
            [.text(posted.voucher.id.uuidString)]
        )) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(
                sqliteError.message.localizedCaseInsensitiveContains("foreign key"),
                "Expected foreign-key protection, got \(sqliteError.message)"
            )
        }

        let voucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_vouchers WHERE id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(voucherCount, 1)

        let afterDeleteCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM trn_accounting_compat WHERE voucher_id = ?",
            bind: [.text(posted.voucher.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(afterDeleteCount, 2)
    }

    func testMarkUsedThrowsWhenAccountMissing() throws {
        let tc = try TestCompany.make()
        let missingId = UUID()

        XCTAssertThrowsError(try AccountRepository(db: tc.db).markUsed(missingId)) { error in
            guard case AppError.notFound(let message) = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(message, "Account not found for usage update")
        }
    }

    func testVoucherPostRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure
            BEFORE UPDATE OF last_used_at ON avelo_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced markUsed failure"))
        }

        let voucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_vouchers",
            row: { $0.int(0) }
        )
        XCTAssertEqual(voucherCount, 0)

        let lineCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM trn_accounting_compat",
            row: { $0.int(0) }
        )
        XCTAssertEqual(lineCount, 0)
    }

    func testVoucherEditRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Original", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure_on_edit
            BEFORE UPDATE OF last_used_at ON avelo_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced edit markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.edit(posted.voucher.id, with: tc.draft(on: "2024-06-02", narration: "Edited", lines: [
            tc.line(tc.cashId, 60000, .debit),
            tc.line(tc.salesId, 60000, .credit)
        ]), in: tc.fy)) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced edit markUsed failure"))
        }

        let storedVoucher = try XCTUnwrap(svc.findById(posted.voucher.id))
        XCTAssertEqual(storedVoucher.date, DateFormatters.parseDate("2024-06-01")!)
        XCTAssertEqual(storedVoucher.narration, "Original")
        XCTAssertEqual(storedVoucher.totalPaise, 50000)

        let storedLines = try svc.lines(for: posted.voucher.id)
        XCTAssertEqual(storedLines.count, 2)
        XCTAssertEqual(storedLines.map(\.amountPaise), [50000, 50000])

        let editAuditCount = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .voucherEdited)
        ).count
        XCTAssertEqual(editAuditCount, 0)
    }

    func testVoucherReverseRollsBackIfAccountUsageUpdateFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Original", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_test_mark_used_failure_on_reverse
            BEFORE UPDATE OF last_used_at ON avelo_accounts
            FOR EACH ROW
            WHEN NEW.id = '\(tc.salesId.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced reverse markUsed failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.reverse(posted.voucher.id, reason: "cleanup")) { error in
            guard case AppError.database(let sqliteError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            XCTAssertTrue(sqliteError.message.contains("forced reverse markUsed failure"))
        }

        let reversalCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_vouchers WHERE reversal_of_id = ? AND is_reversal = 1",
            bind: [.text(posted.voucher.id.uuidString)],
            row: { $0.int(0) }
        )
        XCTAssertEqual(reversalCount, 0)

        let reverseAuditCount = try AuditRepository(db: tc.db).list(
            filter: .init(companyId: tc.companyId, action: .voucherReversed)
        ).count
        XCTAssertEqual(reverseAuditCount, 0)

        let totalVoucherCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_vouchers",
            row: { $0.int(0) }
        )
        XCTAssertEqual(totalVoucherCount, 1)
    }
}
