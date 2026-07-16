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

    func testCheckedTotalsThrowOnOverflow() {
        let d = draft([line(Int64.max, .debit), line(1, .debit), line(Int64.max, .credit)])
        XCTAssertThrowsError(try d.checkedTotals()) { error in
            guard case AppError.businessRule(let message) = error else {
                return XCTFail("Expected businessRule overflow, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("overflow"))
        }
    }

    func testOverflowingDraftFailsClosedForNonThrowingHelpers() {
        let d = draft([line(Int64.max, .debit), line(1, .debit), line(Int64.max, .credit)])
        XCTAssertEqual(d.totalDebitPaise, 0)
        XCTAssertEqual(d.totalCreditPaise, 0)
        XCTAssertEqual(d.differencePaise, 0)
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

    // AVL-P0-020: `MoneyTextField`'s `onCommit` (fired on Return/Enter, not on
    // a plain blur) drives `addLine()` in the voucher-line grid so pressing
    // Enter on an amount field appends a new blank line per the PRD's
    // "Enter on amount adds a new line" keyboard contract.
    @MainActor
    func testAddLineAppendsBlankRowPreservingExistingLines() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        let originalCount = vm.lines.count
        let firstLineId = vm.lines[0].id

        vm.addLine()

        XCTAssertEqual(vm.lines.count, originalCount + 1)
        XCTAssertEqual(vm.lines[0].id, firstLineId, "existing lines are preserved, not replaced")
        XCTAssertNil(vm.lines.last?.accountId)
    }

    // AVL-P2-011: duplicate voucher (⌥2) reuses the draft-recovery preload path.

    @MainActor
    func testDuplicateDraftPreloadsFreshEditorWithSourceVoucherLinesAndNewNumber() throws {
        let tc = try TestCompany.make()
        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: VoucherDraft(
                mode: .create, voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.cashId, narration: "Original sale",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 100_000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100_000, side: .credit)
                ]
            ),
            in: tc.fy
        ).voucher
        let lines = try VoucherService(db: tc.db, companyId: tc.companyId).lines(for: posted.id)

        let duplicateEntry = VoucherEditViewModel.duplicateDraft(from: posted, lines: lines)

        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .sales)
        vm.loadFromRecoveredDraft(duplicateEntry)

        XCTAssertEqual(vm.narration, "Original sale")
        XCTAssertEqual(vm.partyAccountId, tc.cashId)
        XCTAssertEqual(vm.lines.count, 2)
        XCTAssertEqual(vm.lines[0].amount, "1000.00")

        // Posting the duplicate produces a distinct voucher with its own number.
        let secondPosted = try VoucherService(db: tc.db, companyId: tc.companyId).post(draft: vm.buildDraft(), in: tc.fy).voucher
        XCTAssertNotEqual(secondPosted.id, posted.id)
        XCTAssertNotEqual(secondPosted.number, posted.number)
    }

    @MainActor
    func testDuplicatePaymentDraftKeepsOnlyCounterpartLines() throws {
        let tc = try TestCompany.make()
        try assertSingleEntryDuplicateRecovery(
            tc,
            type: .payment,
            cashBankAccountId: tc.cashId,
            sourceSide: .credit,
            counterpartAccountId: tc.rentId,
            counterpartSide: .debit
        )
    }

    @MainActor
    func testDuplicateReceiptDraftKeepsOnlyCounterpartLines() throws {
        let tc = try TestCompany.make()
        try assertSingleEntryDuplicateRecovery(
            tc,
            type: .receipt,
            cashBankAccountId: tc.cashId,
            sourceSide: .debit,
            counterpartAccountId: tc.salesId,
            counterpartSide: .credit
        )
    }

    @MainActor
    func testDuplicateContraDraftKeepsOnlyCounterpartLines() throws {
        let tc = try TestCompany.make()
        let destinationBankId = UUID()
        try assertSingleEntryDuplicateRecovery(
            tc,
            type: .contra,
            cashBankAccountId: destinationBankId,
            sourceSide: .debit,
            counterpartAccountId: tc.cashId,
            counterpartSide: .credit
        )
    }

    @MainActor
    private func assertSingleEntryDuplicateRecovery(_ tc: TestCompany,
                                                    type: VoucherType.Code,
                                                    cashBankAccountId: Account.ID,
                                                    sourceSide: LedgerSide,
                                                    counterpartAccountId: Account.ID,
                                                    counterpartSide: LedgerSide) throws {
        let voucher = Voucher(
            companyId: tc.companyId,
            financialYearId: tc.fy.id,
            voucherTypeCode: type,
            number: "\(type.rawValue)-SOURCE",
            date: tc.fy.startDate,
            narration: "Source \(type.rawValue)",
            totalPaise: 12_500
        )
        // Deliberately put the cash/bank line second: source selection must
        // follow the voucher-type side, not assume an existing line position.
        let sourceLines = [
            LedgerLine(
                companyId: tc.companyId,
                voucherId: voucher.id,
                accountId: counterpartAccountId,
                amountPaise: 12_500,
                side: counterpartSide,
                lineOrder: 0
            ),
            LedgerLine(
                companyId: tc.companyId,
                voucherId: voucher.id,
                accountId: cashBankAccountId,
                amountPaise: 12_500,
                side: sourceSide,
                lineOrder: 1
            )
        ]

        let duplicate = VoucherEditViewModel.duplicateDraft(from: voucher, lines: sourceLines)
        let vm = singleEntryVM(tc, type: type)
        vm.loadFromRecoveredDraft(duplicate)

        XCTAssertEqual(duplicate.accountLedgerId, cashBankAccountId)
        XCTAssertEqual(vm.accountLedgerId, cashBankAccountId)
        XCTAssertEqual(vm.lines.compactMap(\.accountId), [counterpartAccountId])

        let rebuilt = vm.buildDraft()
        XCTAssertEqual(rebuilt.lines.compactMap(\.accountId), [cashBankAccountId, counterpartAccountId])
        XCTAssertEqual(rebuilt.lines.map(\.side), [sourceSide, counterpartSide])
    }

    // AVL-P0-018: draft autosave and crash recovery.

    @MainActor
    func testLoadFromRecoveredDraftPopulatesFieldsAndReusesDraftId() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        let originalDraftId = vm.draftId

        let bankLedgerId = UUID()
        let entry = VoucherEntryDraft(
            companyId: tc.companyId,
            voucherTypeCode: .payment,
            date: DateFormatters.parseDate("2024-05-01")!,
            partyAccountId: tc.cashId,
            narration: "Recovered narration",
            billReferenceType: .advance,
            billReferenceNumber: "REF-9",
            chequeNumber: "CHQ-9",
            chequeDueDate: DateFormatters.parseDate("2024-05-15"),
            accountLedgerId: bankLedgerId,
            linesJSON: #"[{"accountId":null,"amount":"250.00","side":"credit","taxCode":null,"costCenter":null}]"#
        )

        vm.loadFromRecoveredDraft(entry)

        XCTAssertNotEqual(vm.draftId, originalDraftId, "continuing to edit a resumed draft must update its own row, not a fresh one")
        XCTAssertEqual(vm.draftId, entry.id)
        XCTAssertEqual(vm.narration, "Recovered narration")
        XCTAssertEqual(vm.partyAccountId, tc.cashId)
        XCTAssertEqual(vm.billReferenceType, .advance)
        XCTAssertEqual(vm.billReferenceNumber, "REF-9")
        XCTAssertEqual(vm.chequeNumber, "CHQ-9")
        XCTAssertNotNil(vm.chequeDueDate)
        XCTAssertEqual(vm.accountLedgerId, bankLedgerId)
        XCTAssertEqual(vm.lines.count, 1)
        XCTAssertEqual(vm.lines[0].amount, "250.00")
        XCTAssertEqual(vm.lines[0].side, .credit)
    }

    @MainActor
    func testLoadFromRecoveredDraftIgnoresEmptyLinesRatherThanClearingTheEditor() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        let entry = VoucherEntryDraft(companyId: tc.companyId, voucherTypeCode: .journal, date: Date(), linesJSON: "[]")

        vm.loadFromRecoveredDraft(entry)

        XCTAssertEqual(vm.lines.count, 1, "the default blank line is kept when the recovered draft had no lines")
    }

    @MainActor
    func testScheduleAutosavePersistsDraftAfterDebounceWindow() async throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .payment)
        vm.narration = "In-progress entry"

        vm.scheduleAutosave()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let saved = try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId)
        XCTAssertEqual(saved?.id, vm.draftId)
        XCTAssertEqual(saved?.narration, "In-progress entry")
        XCTAssertEqual(saved?.voucherTypeCode, .payment)
    }

    /// AVL-P0-018 follow-up: single-entry-mode autosave must persist the
    /// cash/bank ledger (MigrationV021's `account_ledger_id`), not just the
    /// particulars, so crash recovery doesn't force the user to re-pick it.
    @MainActor
    func testScheduleAutosavePersistsAccountLedgerIdInSingleEntryMode() async throws {
        let tc = try TestCompany.make()
        let vm = singleEntryVM(tc, type: .payment)
        let bankLedgerId = UUID()
        vm.accountLedgerId = bankLedgerId

        vm.scheduleAutosave()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let saved = try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId)
        XCTAssertEqual(saved?.accountLedgerId, bankLedgerId)
    }

    @MainActor
    func testScheduleAutosaveDoesNothingInEditMode() async throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal, existingId: UUID())
        vm.narration = "Should not autosave"

        vm.scheduleAutosave()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertNil(try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId))
    }

    @MainActor
    func testDeleteDraftRemovesTheAutosavedRow() async throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        vm.scheduleAutosave()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertNotNil(try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId))

        vm.deleteDraft()

        XCTAssertNil(try VoucherDraftRepository(db: tc.db).mostRecent(companyId: tc.companyId))
    }

    @MainActor
    func testRemoveLineDropsOnlyTheTargetedRow() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        vm.addLine()
        vm.addLine()
        let target = vm.lines[1].id
        let remainingIds = vm.lines.filter { $0.id != target }.map(\.id)

        vm.removeLine(target)

        XCTAssertEqual(vm.lines.map(\.id), remainingIds)
    }

    // AVL-P1-035 (bill-wise allocation UI): EditVoucherSheet must surface the
    // same bill reference fields NewVoucherSheet does — the service/model
    // layer already round-tripped them, but the edit-mode form was missing
    // the controls, so an accountant editing a voucher could never see or
    // change its bill allocation.
    @MainActor
    func testEditModeLoadRestoresBillReferenceFromPostedVoucher() throws {
        let tc = try TestCompany.make()
        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.cashId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-501",
                narration: "Sale on credit",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 100_000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 100_000, side: .credit)
                ]
            ),
            in: tc.fy
        ).voucher

        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .sales, existingId: posted.id)
        vm.load(accounts: [], initialDate: posted.date)

        XCTAssertEqual(vm.billReferenceType, .newRef)
        XCTAssertEqual(vm.billReferenceNumber, "INV-501")
    }

    // MARK: - Tally single-entry mode

    @MainActor
    private func singleEntryVM(_ tc: TestCompany, type: VoucherType.Code) -> VoucherEditViewModel {
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: type)
        vm.singleEntryMode = true
        return vm
    }

    @MainActor
    func testContraSingleEntryComposesBalancedDraft() throws {
        let tc = try TestCompany.make()
        let vm = singleEntryVM(tc, type: .contra)
        let bank = UUID(), cash = UUID()
        vm.accountLedgerId = bank
        vm.lines = [.init(accountId: cash, amount: "5000.00", side: .debit)] // side is ignored

        let d = vm.buildDraft()

        XCTAssertEqual(d.lines.count, 2)
        // Account line first: destination bank debited with the particulars total.
        XCTAssertEqual(d.lines[0].accountId, bank)
        XCTAssertEqual(d.lines[0].side, .debit)
        XCTAssertEqual(d.lines[0].amountPaise, 500_000)
        // Particulars credited regardless of the row's raw side.
        XCTAssertEqual(d.lines[1].accountId, cash)
        XCTAssertEqual(d.lines[1].side, .credit)
        XCTAssertTrue(d.isBalanced)
        XCTAssertTrue(vm.isBalanced)
    }

    /// Live-reported bug, root-caused 2026-07-17: posting silently failed
    /// with "no error, no toast, nothing" for EVERY voucher. Root cause was
    /// two bugs stacked: (1) `Currency.parseRupeeInput("")` returns 0, not
    /// nil, so `buildWorkflowInputs()` set tdsTaxPaise/tcsTaxPaise to
    /// Optional(0) for every voucher that never touched TDS/TCS — which
    /// VoucherService.post(draft:in:workflow:) gates on being nil (TDS/TCS
    /// is deferred outside the frozen schema), so posting *always* threw
    /// featureUnavailable; (2) that error was invisible because it routed
    /// through env.showError() → a root-level `.alert`, which AppKit can't
    /// present over an already-active `.sheet` (NewVoucherSheet itself).
    /// This test exercises the exact real path a live Post button uses —
    /// VoucherEditViewModel.buildWorkflowInputs() feeding
    /// VoucherService.post(draft:in:workflow:) — which no test did before
    /// (zero prior references to buildWorkflowInputs() in the whole suite).
    @MainActor
    func testPostingAPlainVoucherThroughBuildWorkflowInputsSucceeds() throws {
        let tc = try TestCompany.make()
        let vm = singleEntryVM(tc, type: .payment)
        vm.date = DateFormatters.parseDate("2024-06-01")!
        vm.accountLedgerId = tc.cashId
        vm.lines = [.init(accountId: tc.rentId, amount: "100.00", side: .credit)]

        XCTAssertTrue(vm.isBalanced)
        let result = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: vm.buildDraft(), in: tc.fy, workflow: vm.buildWorkflowInputs()
        )
        XCTAssertEqual(result.voucher.voucherTypeCode, .payment)
        XCTAssertEqual(result.voucher.totalPaise, 10_000)
    }

    @MainActor
    func testPaymentSingleEntryCreditsTheAccountLedger() throws {
        let tc = try TestCompany.make()
        let vm = singleEntryVM(tc, type: .payment)
        vm.accountLedgerId = UUID()
        vm.lines = [
            .init(accountId: UUID(), amount: "100.00", side: .credit),
            .init(accountId: UUID(), amount: "250.00", side: .credit)
        ]

        let d = vm.buildDraft()

        XCTAssertEqual(d.lines[0].side, .credit)          // cash/bank pays out
        XCTAssertEqual(d.lines[0].amountPaise, 35_000)
        XCTAssertTrue(d.lines.dropFirst().allSatisfy { $0.side == .debit })
        XCTAssertTrue(d.isBalanced)
    }

    @MainActor
    func testSingleEntryNotBalancedWithoutAccountOrAmounts() throws {
        let tc = try TestCompany.make()
        let vm = singleEntryVM(tc, type: .receipt)
        XCTAssertFalse(vm.isBalanced)                     // no account, no amounts
        vm.accountLedgerId = UUID()
        XCTAssertFalse(vm.isBalanced)                     // still no amounts
        vm.lines = [.init(accountId: UUID(), amount: "10.00", side: .credit)]
        XCTAssertTrue(vm.isBalanced)
    }

    func testSingleEntryVoucherValidationAcceptsEligibleCashBankPatterns() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)

        let payment = tc.draft(type: .payment, on: "2024-06-01", lines: [
            tc.line(tc.rentId, 12_500, .debit),
            tc.line(tc.cashId, 12_500, .credit)
        ])
        let receipt = tc.draft(type: .receipt, on: "2024-06-01", lines: [
            tc.line(tc.cashId, 12_500, .debit),
            tc.line(tc.salesId, 12_500, .credit)
        ])

        XCTAssertEqual(try service.validate(draft: payment, in: tc.fy), .valid)
        XCTAssertEqual(try service.validate(draft: receipt, in: tc.fy), .valid)

        try tc.db.execute(
            "UPDATE avelo_accounts SET is_bank_account = 1 WHERE id = ?",
            [.text(tc.salesId.uuidString)]
        )
        let contra = tc.draft(type: .contra, on: "2024-06-01", lines: [
            tc.line(tc.cashId, 12_500, .debit),
            tc.line(tc.salesId, 12_500, .credit)
        ])

        XCTAssertEqual(try service.validate(draft: contra, in: tc.fy), .valid)
    }

    func testSingleEntryVoucherPostingRejectsIneligibleCashBankPatterns() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let invalidDrafts = [
            tc.draft(type: .payment, on: "2024-06-01", lines: [
                tc.line(tc.rentId, 12_500, .debit),
                tc.line(tc.salesId, 12_500, .credit)
            ]),
            tc.draft(type: .receipt, on: "2024-06-01", lines: [
                tc.line(tc.rentId, 12_500, .debit),
                tc.line(tc.salesId, 12_500, .credit)
            ]),
            tc.draft(type: .contra, on: "2024-06-01", lines: [
                tc.line(tc.cashId, 12_500, .debit),
                tc.line(tc.rentId, 12_500, .credit)
            ])
        ]

        for draft in invalidDrafts {
            XCTAssertThrowsError(try service.post(draft: draft, in: tc.fy)) { error in
                guard case AppError.validation(let validation) = error else {
                    return XCTFail("Expected validation error, got \(error)")
                }
                XCTAssertEqual(validation.code, .internal)
                XCTAssertTrue(validation.message.contains("cash/bank"))
            }
        }
    }

    func testSingleEntryVoucherPostingRejectsWrongCashBankSide() throws {
        let tc = try TestCompany.make()
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let invalidDrafts = [
            tc.draft(type: .payment, on: "2024-06-01", lines: [
                tc.line(tc.cashId, 12_500, .debit),
                tc.line(tc.rentId, 12_500, .credit)
            ]),
            tc.draft(type: .receipt, on: "2024-06-01", lines: [
                tc.line(tc.salesId, 12_500, .debit),
                tc.line(tc.cashId, 12_500, .credit)
            ])
        ]

        for draft in invalidDrafts {
            XCTAssertThrowsError(try service.post(draft: draft, in: tc.fy)) { error in
                guard case AppError.validation(let validation) = error else {
                    return XCTFail("Expected validation error, got \(error)")
                }
                XCTAssertEqual(validation.code, .internal)
                XCTAssertTrue(validation.message.contains("cash/bank"))
            }
        }

        try tc.db.execute(
            "UPDATE avelo_accounts SET is_bank_account = 1 WHERE id IN (?, ?)",
            [.text(tc.rentId.uuidString), .text(tc.salesId.uuidString)]
        )
        let contraWithMultipleDestinationLedgers = tc.draft(type: .contra, on: "2024-06-01", lines: [
            tc.line(tc.cashId, 5_000, .debit),
            tc.line(tc.rentId, 7_500, .debit),
            tc.line(tc.salesId, 12_500, .credit)
        ])
        XCTAssertThrowsError(try service.post(draft: contraWithMultipleDestinationLedgers, in: tc.fy)) { error in
            guard case AppError.validation(let validation) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .internal)
            XCTAssertTrue(validation.message.contains("cash/bank"))
        }
    }

    @MainActor
    func testAddLinePrefillsBalancingAmountInDoubleEntry() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .journal)
        vm.lines = [.init(accountId: UUID(), amount: "750.00", side: .debit)]

        vm.addLine()

        let added = try XCTUnwrap(vm.lines.last)
        XCTAssertEqual(added.side, .credit)
        XCTAssertEqual(Currency.parseRupeeInput(added.amount), 75_000)
    }

    @MainActor
    func testIsCashOrBankClassification() throws {
        let tc = try TestCompany.make()
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id, initialType: .contra)
        let bankGroup = AccountGroup(companyId: tc.companyId, code: "BANK_ACCOUNTS", name: "Bank Accounts", nature: .assets)
        let assetGroup = AccountGroup(companyId: tc.companyId, code: "CURRENT_ASSETS", name: "Current Assets", nature: .assets)
        vm.groups = [bankGroup, assetGroup]

        func account(_ code: String, group: AccountGroup, bankFlag: Bool = false) -> Account {
            Account(companyId: tc.companyId, groupId: group.id, code: code, name: code, isBankAccount: bankFlag)
        }

        XCTAssertTrue(vm.isCashOrBank(account("BANK_HDFC", group: bankGroup)))            // by group
        XCTAssertTrue(vm.isCashOrBank(account("ODD_BANK", group: assetGroup, bankFlag: true))) // by flag
        XCTAssertTrue(vm.isCashOrBank(account("CASH_IN_HAND", group: assetGroup)))        // legacy seed cash ledger
        XCTAssertFalse(vm.isCashOrBank(account("SUNDRY_DEBTORS", group: assetGroup)))
    }
}
