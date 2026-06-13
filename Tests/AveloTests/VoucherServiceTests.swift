import XCTest
@testable import Avelo

final class VoucherServiceTests: XCTestCase {

    private func movement(_ db: SQLiteDatabase, account: Account.ID) throws -> (dr: Int64, cr: Int64) {
        let r = try db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END),0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END),0) AS cr
            FROM avelo_ledger_lines WHERE account_id = ?
            """,
            bind: [.text(account.uuidString)]
        ) { ($0.int("dr"), $0.int("cr")) }
        return (r?.0 ?? 0, r?.1 ?? 0)
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
            FROM avelo_ledger_lines
            """
        ) { ($0.int("dr"), $0.int("cr")) }
        XCTAssertEqual(totals?.0, totals?.1)
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
            FROM avelo_ledger_lines
            """
        ) { ($0.int("dr"), $0.int("cr"), $0.int("c")) }
        XCTAssertEqual(totals?.0, totals?.1)
        XCTAssertEqual(totals?.2, 25)
    }

    func testPostBatchCommitsEarlierVouchersBeforeLaterFailure() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let drafts: [VoucherDraft] = [
            tc.draft(on: "2024-06-01", lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 1000, .credit)
            ]),
            tc.draft(on: "2024-06-02", lines: [
                tc.line(tc.cashId, 1000, .debit),
                tc.line(tc.salesId, 900, .credit)
            ])
        ]

        XCTAssertThrowsError(try svc.postBatch(drafts, in: tc.fy))

        let voucherCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) } ?? 0
        let lineCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_ledger_lines") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 1)
        XCTAssertEqual(lineCount, 2)
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

    func testWorkflowInputsPersistBillChequeAndTaxRecords() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.salesId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Workflow test",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 118000, side: .debit),
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
        ).voucher

        let allocations = try tc.db.queryOne(
            "SELECT kind, reference_number, allocated_paise FROM avelo_bill_allocations WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { ($0.text("kind"), $0.optionalText("reference_number"), $0.int("allocated_paise")) }
        XCTAssertEqual(allocations?.0, BillAllocationKind.newRef.rawValue)
        XCTAssertEqual(allocations?.1, "INV-77")
        XCTAssertEqual(allocations?.2, 118000)

        let cheque = try tc.db.queryOne(
            "SELECT cheque_number, status FROM avelo_cheques WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { ($0.text("cheque_number"), $0.text("status")) }
        XCTAssertEqual(cheque?.0, "CHQ-123")
        XCTAssertEqual(cheque?.1, ChequeStatus.issued.rawValue)

        let tds = try tc.db.queryOne(
            "SELECT section_code, tax_paise FROM avelo_tds_records WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { ($0.text("section_code"), $0.int("tax_paise")) }
        XCTAssertEqual(tds?.0, "194C")
        XCTAssertEqual(tds?.1, 5000)

        let tcs = try tc.db.queryOne(
            "SELECT section_code, tax_paise FROM avelo_tcs_records WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { ($0.text("section_code"), $0.int("tax_paise")) }
        XCTAssertEqual(tcs?.0, "206C")
        XCTAssertEqual(tcs?.1, 3000)
    }

    func testPostWithWorkflowRollsBackVoucherWhenWorkflowInsertFails() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        try tc.db.execute(
            """
            CREATE TRIGGER trg_bill_allocations_fail
            BEFORE INSERT ON avelo_bill_allocations
            BEGIN
                SELECT RAISE(ABORT, 'forced workflow failure');
            END;
            """
        )

        XCTAssertThrowsError(try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.salesId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Workflow rollback test",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 118000, side: .debit),
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
                tdsTaxPaise: 5000
            )
        ))

        let voucherCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) } ?? 0
        let allocationCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_bill_allocations") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 0)
        XCTAssertEqual(allocationCount, 0)
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

    func testHistoricalEditAllowsNewlyDeactivatedAccountsWhenLinesUnchanged() throws {
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
        XCTAssertNoThrow(try svc.edit(posted.voucher.id, with: edited, in: tc.fy))
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

    func testVoucherDeleteDoesNotCascadeLedgerLinesSilently() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

        let beforeDeleteCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_ledger_lines WHERE voucher_id = ?",
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
            "SELECT COUNT(*) FROM avelo_ledger_lines WHERE voucher_id = ?",
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
            "SELECT COUNT(*) FROM avelo_ledger_lines",
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

    func testVoucherEditRecomputesWorkflowRowsWhenTotalsChange() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.salesId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Workflow edit test",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 118000, side: .debit),
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
        ).voucher

        let edited = VoucherDraft(
            mode: .edit(originalVoucherId: posted.id),
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.salesId,
            billReferenceType: .newRef,
            billReferenceNumber: "INV-77",
            narration: "Workflow edit test",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 128000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 110000, side: .credit),
                .init(accountId: tc.rentId, amountPaise: 18000, side: .credit)
            ]
        )

        _ = try svc.edit(posted.id, with: edited, in: tc.fy)

        let allocation = try tc.db.queryOne(
            "SELECT allocated_paise FROM avelo_bill_allocations WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(allocation, 128000)

        let tds = try tc.db.queryOne(
            "SELECT base_paise FROM avelo_tds_records WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(tds, 128000)

        let tcs = try tc.db.queryOne(
            "SELECT base_paise FROM avelo_tcs_records WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(tcs, 128000)
    }

    func testVoucherEditPreservesChequeStatusAndZeroTaxWorkflowRows() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.salesId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-88",
                narration: "Workflow status test",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 100000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(
                chequeNumber: "CHQ-888",
                chequeDueDate: DateFormatters.parseDate("2024-06-15")!,
                tdsSectionCode: "194C",
                tdsTaxPaise: 0
            )
        ).voucher

        try tc.db.execute(
            "UPDATE avelo_cheques SET status = ? WHERE voucher_id = ?",
            [.text(ChequeStatus.cleared.rawValue), .text(posted.id.uuidString)]
        )

        let edited = VoucherDraft(
            mode: .edit(originalVoucherId: posted.id),
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.salesId,
            billReferenceType: .newRef,
            billReferenceNumber: "INV-88",
            narration: "Workflow status test edited",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 100000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 100000, side: .credit)
            ]
        )

        _ = try svc.edit(posted.id, with: edited, in: tc.fy)

        let cheque = try tc.db.queryOne(
            "SELECT status FROM avelo_cheques WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { $0.text(0) }
        XCTAssertEqual(cheque, ChequeStatus.cleared.rawValue)

        let tds = try tc.db.queryOne(
            "SELECT tax_paise FROM avelo_tds_records WHERE voucher_id = ?",
            bind: [.text(posted.id.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(tds, 0)
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
