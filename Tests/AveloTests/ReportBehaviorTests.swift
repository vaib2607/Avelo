import XCTest
@testable import Avelo

final class ReportBehaviorTests: XCTestCase {

    private struct SeededReportCompany {
        let db: SQLiteDatabase
        let companyId: Company.ID
        let fy: FinancialYear
        let cashId: Account.ID
        let salesId: Account.ID
        let debtorsId: Account.ID
        let creditorsId: Account.ID
        let rentId: Account.ID
        let purchaseId: Account.ID
        let cgstOutputId: Account.ID
        let sgstOutputId: Account.ID
    }

    private struct SeededActivity {
        let openingDaySale: Voucher
        let debtorSale: Voucher
        let rentPayment: Voucher
        let gstCollection: Voucher
        let supplierBill: Voucher
    }

    private func makeSeededCompany() throws -> SeededReportCompany {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)

        let companyId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())
        try db.execute(
            "INSERT INTO avelo_companies (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [.text(companyId.uuidString), .text("Report Co"), .text(now), .text(now)]
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
            [
                .text(fyId.uuidString), .text(companyId.uuidString), .text("2024-25"),
                .date(start), .date(end), .date(start), .text(now)
            ]
        )
        let fy = FinancialYear(
            id: fyId,
            companyId: companyId,
            label: "2024-25",
            startDate: start,
            endDate: end,
            booksBeginDate: start
        )

        try SeedLoader().loadDefaults(into: db, companyId: companyId, financialYearId: fy.id)

        let accounts = AccountRepository(db: db)
        return SeededReportCompany(
            db: db,
            companyId: companyId,
            fy: fy,
            cashId: try XCTUnwrap(accounts.findByCode("CASH_IN_HAND", companyId: companyId)?.id),
            salesId: try XCTUnwrap(accounts.findByCode("SALES", companyId: companyId)?.id),
            debtorsId: try XCTUnwrap(accounts.findByCode("SUNDRY_DEBTORS", companyId: companyId)?.id),
            creditorsId: try XCTUnwrap(accounts.findByCode("SUNDRY_CREDITORS", companyId: companyId)?.id),
            rentId: try XCTUnwrap(accounts.findByCode("RENT_EXPENSE", companyId: companyId)?.id),
            purchaseId: try XCTUnwrap(accounts.findByCode("PURCHASE", companyId: companyId)?.id),
            cgstOutputId: try XCTUnwrap(accounts.findByCode("CGST_OUTPUT", companyId: companyId)?.id),
            sgstOutputId: try XCTUnwrap(accounts.findByCode("SGST_OUTPUT", companyId: companyId)?.id)
        )
    }

    @discardableResult
    private func seedActivity(_ tc: SeededReportCompany) throws -> SeededActivity {
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let openingDaySale = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-04-01")!,
            narration: "Opening day sale",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 10000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 10000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let debtorSale = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-06-01")!,
            narration: "Debtor sale",
            lines: [
                .init(accountId: tc.debtorsId, amountPaise: 15000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 15000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let rentPayment = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-07-01")!,
            narration: "Rent payment",
            lines: [
                .init(accountId: tc.rentId, amountPaise: 20000, side: .debit),
                .init(accountId: tc.cashId, amountPaise: 20000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let gstCollection = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-08-01")!,
            narration: "GST collection",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 1800, side: .debit),
                .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
            ]
        ), in: tc.fy).voucher

        let supplierBill = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-09-01")!,
            narration: "Supplier bill",
            lines: [
                .init(accountId: tc.purchaseId, amountPaise: 7000, side: .debit),
                .init(accountId: tc.creditorsId, amountPaise: 7000, side: .credit)
            ]
        ), in: tc.fy).voucher

        return SeededActivity(
            openingDaySale: openingDaySale,
            debtorSale: debtorSale,
            rentPayment: rentPayment,
            gstCollection: gstCollection,
            supplierBill: supplierBill
        )
    }

    func testDayBookRespectsDateRangeAndOrdering() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let rows = try ReportService(db: tc.db, companyId: tc.companyId).dayBook(
            fromDate: DateFormatters.parseDate("2024-06-01")!,
            toDate: DateFormatters.parseDate("2024-08-01")!
        )

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.narration), ["Debtor sale", "Rent payment", "GST collection"])
        XCTAssertEqual(rows.map(\.totalDebitPaise), [7500, 10000, 900])
        XCTAssertEqual(rows.map(\.totalCreditPaise), [7500, 10000, 900])
    }

    func testOutstandingRespectsDirectionAndAsOfBoundary() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = ReportService(db: tc.db, companyId: tc.companyId)

        let receivablesBeforeSale = try report.outstanding(
            asOfDate: DateFormatters.parseDate("2024-05-31")!,
            direction: .receivable
        )
        XCTAssertEqual(receivablesBeforeSale.rows.count, 0)
        XCTAssertEqual(receivablesBeforeSale.totalPaise, 0)

        let receivablesAfterSale = try report.outstanding(
            asOfDate: DateFormatters.parseDate("2024-08-31")!,
            direction: .receivable
        )
        XCTAssertEqual(receivablesAfterSale.rows.count, 1)
        XCTAssertEqual(receivablesAfterSale.rows.first?.partyName, "Sundry Debtors")
        XCTAssertEqual(receivablesAfterSale.rows.first?.amountPaise, 15000)
        XCTAssertEqual(receivablesAfterSale.totalPaise, 15000)

        let payablesAfterBill = try report.outstanding(
            asOfDate: DateFormatters.parseDate("2024-09-30")!,
            direction: .payable
        )
        XCTAssertEqual(payablesAfterBill.rows.count, 1)
        XCTAssertEqual(payablesAfterBill.rows.first?.partyName, "Sundry Creditors")
        XCTAssertEqual(payablesAfterBill.rows.first?.amountPaise, -7000)
        XCTAssertEqual(payablesAfterBill.totalPaise, -7000)
    }

    func testOutstandingUsesBillWiseAllocationsAndAgeBuckets() throws {
        let tc = try makeSeededCompany()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-04-01")!,
                partyAccountId: tc.debtorsId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-001",
                narration: "Bill one",
                lines: [
                    .init(accountId: tc.debtorsId, amountPaise: 50000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 50000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-001")
        )

        _ = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-04-15")!,
                partyAccountId: tc.debtorsId,
                billReferenceType: .agstRef,
                billReferenceNumber: "INV-001",
                narration: "Partial settlement",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 20000, side: .debit),
                    .init(accountId: tc.debtorsId, amountPaise: 20000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .agstRef, billAllocationNumber: "INV-001")
        )

        let outstanding = try ReportService(db: tc.db, companyId: tc.companyId).outstanding(
            asOfDate: DateFormatters.parseDate("2024-05-20")!,
            direction: .receivable
        )

        XCTAssertEqual(outstanding.rows.count, 1)
        XCTAssertEqual(outstanding.totalPaise, 30000)
        let row = try XCTUnwrap(outstanding.rows.first)
        XCTAssertEqual(row.amountPaise, 30000)
        XCTAssertEqual(row.age31to60Paise, 30000)
        XCTAssertEqual(row.age0to30Paise, 0)
        XCTAssertEqual(row.age61to90Paise, 0)
        XCTAssertEqual(row.age90PlusPaise, 0)
        XCTAssertEqual(row.ageInDays, 49)
    }

    func testGstSummaryRespectsDateRangeAndBucketTotals() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let gst = try ReportService(db: tc.db, companyId: tc.companyId).gstSummary(
            fromDate: DateFormatters.parseDate("2024-08-01")!,
            toDate: DateFormatters.parseDate("2024-08-31")!
        )

        let outputByLabel = Dictionary(uniqueKeysWithValues: gst.output.map { ($0.label, $0.amountPaise) })
        XCTAssertEqual(outputByLabel["CGST OUTPUT"], 900)
        XCTAssertEqual(outputByLabel["SGST OUTPUT"], 900)
        XCTAssertEqual(gst.netPayablePaise, 1800)
    }

    func testReportDateBoundariesExcludeLaterActivity() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = ReportService(db: tc.db, companyId: tc.companyId)

        let trialBalance = try report.trialBalance(
            asOfDate: DateFormatters.parseDate("2024-06-30")!,
            financialYearId: tc.fy.id
        )
        XCTAssertEqual(trialBalance.totalDebitPaise, 25000)
        XCTAssertEqual(trialBalance.totalCreditPaise, 25000)

        let dayBook = try report.dayBook(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-06-30")!
        )
        XCTAssertEqual(dayBook.map(\.narration), ["Opening day sale", "Debtor sale"])

        let gstBeforeCollection = try report.gstSummary(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-07-31")!
        )
        XCTAssertEqual(gstBeforeCollection.netPayablePaise, 0)
    }

    func testTrialBalanceUsesActiveFinancialYearStartForMultiYearValidation() throws {
        let tc = try makeSeededCompany()
        let activity = try seedActivity(tc)

        let secondFYStart = DateFormatters.parseDate("2025-04-01")!
        let secondFYEnd = DateFormatters.parseDate("2026-03-31")!
        let secondFYId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())
        try tc.db.execute(
            """
            INSERT INTO avelo_financial_years
            (id, company_id, label, start_date, end_date, books_begin_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(secondFYId.uuidString),
                .text(tc.companyId.uuidString),
                .text("2025-26"),
                .date(secondFYStart),
                .date(secondFYEnd),
                .date(secondFYStart),
                .text(now)
            ]
        )

        // Sanity check that the prior year still has activity the verifier must ignore.
        XCTAssertNotEqual(activity.openingDaySale.financialYearId, secondFYId)

        let report = ReportService(db: tc.db, companyId: tc.companyId)
        let trialBalance = try report.trialBalance(
            asOfDate: secondFYEnd,
            financialYearId: secondFYId
        )

        XCTAssertEqual(trialBalance.totalDebitPaise, trialBalance.totalCreditPaise)
        XCTAssertFalse(trialBalance.rows.isEmpty, "The later FY should still produce a valid report snapshot")
    }

    func testLedgerReportShowsRunningBalanceAndSourceVoucherLinkage() throws {
        let tc = try makeSeededCompany()
        let activity = try seedActivity(tc)

        let ledger = try ReportService(db: tc.db, companyId: tc.companyId).ledger(
            accountId: tc.cashId,
            financialYearId: tc.fy.id,
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-08-31")!
        )

        XCTAssertEqual(ledger.accountId, tc.cashId)
        XCTAssertEqual(ledger.accountName, "Cash-in-Hand")
        XCTAssertEqual(ledger.openingBalancePaise, 0)
        XCTAssertEqual(ledger.rows.count, 3)
        XCTAssertEqual(ledger.rows.map(\.narration), ["Opening day sale", "Rent payment", "GST collection"])
        XCTAssertEqual(ledger.rows.map(\.debitPaise), [10000, 0, 1800])
        XCTAssertEqual(ledger.rows.map(\.creditPaise), [0, 20000, 0])
        XCTAssertEqual(ledger.rows.map(\.balancePaise), [10000, -10000, -8200])
        XCTAssertEqual(ledger.closingBalancePaise, -8200)

        XCTAssertEqual(ledger.rows[0].voucherId, activity.openingDaySale.id)
        XCTAssertEqual(ledger.rows[0].voucherNumber, activity.openingDaySale.number)
        XCTAssertEqual(ledger.rows[1].voucherId, activity.rentPayment.id)
        XCTAssertEqual(ledger.rows[1].voucherNumber, activity.rentPayment.number)
        XCTAssertEqual(ledger.rows[2].voucherId, activity.gstCollection.id)
        XCTAssertEqual(ledger.rows[2].voucherNumber, activity.gstCollection.number)
    }

    func testDayBookRowsCarrySourceVoucherIdentityForDrillDown() throws {
        let tc = try makeSeededCompany()
        let activity = try seedActivity(tc)

        let rows = try ReportService(db: tc.db, companyId: tc.companyId).dayBook(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-09-30")!
        )

        XCTAssertEqual(rows.count, 5)
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        XCTAssertEqual(byId[activity.openingDaySale.id]?.voucherNumber, activity.openingDaySale.number)
        XCTAssertEqual(byId[activity.debtorSale.id]?.voucherNumber, activity.debtorSale.number)
        XCTAssertEqual(byId[activity.rentPayment.id]?.voucherNumber, activity.rentPayment.number)
        XCTAssertEqual(byId[activity.gstCollection.id]?.voucherNumber, activity.gstCollection.number)
        XCTAssertEqual(byId[activity.supplierBill.id]?.voucherNumber, activity.supplierBill.number)
    }

    func testDayBookOrdersBackdatedVouchersByVoucherDate() throws {
        let tc = try makeSeededCompany()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        let laterDatedFirst = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-04-05")!,
            narration: "Current entry",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 2000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 2000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let backdatedSecond = try svc.post(draft: VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-04-01")!,
            narration: "Backdated entry",
            lines: [
                .init(accountId: tc.cashId, amountPaise: 1000, side: .debit),
                .init(accountId: tc.salesId, amountPaise: 1000, side: .credit)
            ]
        ), in: tc.fy).voucher

        let rows = try ReportService(db: tc.db, companyId: tc.companyId).dayBook(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-04-30")!
        )

        XCTAssertEqual(rows.map(\.voucherNumber), [
            backdatedSecond.number,
            laterDatedFirst.number
        ])
        XCTAssertEqual(rows.map(\.narration), ["Backdated entry", "Current entry"])
    }
}
