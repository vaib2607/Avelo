import XCTest
@testable import Avelo

final class VoucherServiceTests: XCTestCase {

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

    func testSalesVoucherReturnsInventoryPromptWhenAutoPromptIsEnabled() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let result = try svc.post(
            draft: tc.draft(type: .sales, on: "2024-06-01", lines: [
                tc.line(tc.cashId, 50000, .debit),
                tc.line(tc.salesId, 50000, .credit)
            ]),
            in: tc.fy
        )

        let prompt = try XCTUnwrap(result.inventoryPrompt)
        XCTAssertEqual(prompt.voucherId, result.voucher.id)
        XCTAssertEqual(prompt.voucherNumber, result.voucher.number)
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
        let lineCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_ledger_lines") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 500)
        XCTAssertEqual(lineCount, 1000)
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
                partyAccountId: tc.cashId,
                narration: "GST rounded invoice",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 11_799, side: .debit),
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

    func testInvoiceEditRecomputesRoundOffDeterministically() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let posted = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.cashId,
                narration: "Rounded invoice",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 11_801, side: .debit),
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
                partyAccountId: tc.cashId,
                narration: "Rounded invoice edited",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 11_798, side: .debit),
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
                    partyAccountId: tc.cashId,
                    narration: "No GST lines",
                    lines: [
                        .init(accountId: tc.cashId, amountPaise: 10_001, side: .debit),
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

    func testWorkflowInputsAreDeferredByFrozenSchema() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: tc.salesId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-77",
                narration: "Deferred workflow test",
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
        )) { error in
            guard case AppError.featureUnavailable(let message) = error else {
                return XCTFail("Expected featureUnavailable, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("deferred"))
        }

        let voucherCount = try tc.db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) } ?? 0
        XCTAssertEqual(voucherCount, 0)
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

    func testCancelMarksVoucherCancelledAndCreatesLinkedReversal() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        let posted = try svc.post(draft: tc.draft(on: "2024-06-01", lines: [
            tc.line(tc.cashId, 50000, .debit),
            tc.line(tc.salesId, 50000, .credit)
        ]), in: tc.fy)

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

        let cash = try movement(tc.db, account: tc.cashId)
        let sales = try movement(tc.db, account: tc.salesId)
        XCTAssertEqual(cash.dr - cash.cr, 0)
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
