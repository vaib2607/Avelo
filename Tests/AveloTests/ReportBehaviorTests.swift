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
        try AuditTestKeySupport.ensureKey(for: companyId)
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
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.debtorsId,
            billReferenceType: .newRef,
            billReferenceNumber: "INV-001",
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
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-09-01")!,
            partyAccountId: tc.creditorsId,
            billReferenceType: .newRef,
            billReferenceNumber: "BILL-001",
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
        XCTAssertEqual(rows.map(\.totalDebitPaise), [15000, 20000, 1800])
        XCTAssertEqual(rows.map(\.totalCreditPaise), [15000, 20000, 1800])
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
        XCTAssertEqual(receivablesAfterSale.rows.first?.referenceNumber, "INV-001")
        XCTAssertEqual(receivablesAfterSale.rows.first?.amountPaise, 15000)
        XCTAssertEqual(receivablesAfterSale.totalPaise, 15000)

        let payablesAfterBill = try report.outstanding(
            asOfDate: DateFormatters.parseDate("2024-09-30")!,
            direction: .payable
        )
        XCTAssertEqual(payablesAfterBill.rows.count, 1)
        XCTAssertEqual(payablesAfterBill.rows.first?.partyName, "Sundry Creditors")
        XCTAssertEqual(payablesAfterBill.rows.first?.referenceNumber, "BILL-001")
        XCTAssertEqual(payablesAfterBill.rows.first?.amountPaise, -7000)
        XCTAssertEqual(payablesAfterBill.totalPaise, -7000)
    }

    func testBillWiseOutstandingConsumesReceiptsFIFOAndHonorsAgainstReference() throws {
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
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-04-05")!,
                partyAccountId: tc.debtorsId,
                billReferenceType: .newRef,
                billReferenceNumber: "INV-002",
                narration: "Bill two",
                lines: [
                    .init(accountId: tc.debtorsId, amountPaise: 30000, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 30000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .newRef, billAllocationNumber: "INV-002")
        )

        _ = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-04-10")!,
                partyAccountId: tc.debtorsId,
                narration: "Receipt on account",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 60000, side: .debit),
                    .init(accountId: tc.debtorsId, amountPaise: 60000, side: .credit)
                ]
            ),
            in: tc.fy
        )

        _ = try svc.post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .receipt,
                date: DateFormatters.parseDate("2024-04-12")!,
                partyAccountId: tc.debtorsId,
                billReferenceType: .agstRef,
                billReferenceNumber: "INV-002",
                narration: "Receipt against bill two",
                lines: [
                    .init(accountId: tc.cashId, amountPaise: 10000, side: .debit),
                    .init(accountId: tc.debtorsId, amountPaise: 10000, side: .credit)
                ]
            ),
            in: tc.fy,
            workflow: VoucherService.WorkflowInputs(billAllocationKind: .agstRef, billAllocationNumber: "INV-002")
        )

        let report = try ReportService(db: tc.db, companyId: tc.companyId).outstanding(
            asOfDate: DateFormatters.parseDate("2024-04-30")!,
            direction: .receivable
        )
        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.rows.first?.partyName, "Sundry Debtors")
        XCTAssertEqual(report.rows.first?.referenceNumber, "INV-002")
        XCTAssertEqual(report.rows.first?.amountPaise, 10000)
        XCTAssertEqual(report.totalPaise, 10000)
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
        XCTAssertEqual(gst.outputTaxablePaise, 0)
        XCTAssertEqual(gst.inputTaxablePaise, 0)
        XCTAssertEqual(gst.outputTaxPaise, 1800)
        XCTAssertEqual(gst.inputTaxPaise, 0)
        XCTAssertEqual(gst.cgstPaise, 900)
        XCTAssertEqual(gst.sgstPaise, 900)
        XCTAssertEqual(gst.igstPaise, 0)
        XCTAssertEqual(gst.cessPaise, 0)
        XCTAssertEqual(gst.netPayablePaise, 1800)
    }

    func testProfitLossRowsCarryTheAmountsShownByTheirSectionTotals() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let report = try ReportService(db: tc.db, companyId: tc.companyId).profitAndLoss(
            fromDate: tc.fy.startDate,
            toDate: tc.fy.endDate,
            financialYearId: tc.fy.id
        )

        let sales = try XCTUnwrap(report.directIncome.rows.first { $0.id == tc.salesId })
        XCTAssertEqual(sales.debitPaise, 0)
        XCTAssertEqual(sales.creditPaise, 25000)

        let rent = try XCTUnwrap(report.indirectExpense.rows.first { $0.id == tc.rentId })
        XCTAssertEqual(rent.debitPaise, 20000)
        XCTAssertEqual(rent.creditPaise, 0)
        XCTAssertEqual(report.directIncome.rows.reduce(0) { $0 + $1.creditPaise - $1.debitPaise }, report.directIncome.totalPaise)
        XCTAssertEqual(report.indirectExpense.rows.reduce(0) { $0 + $1.debitPaise - $1.creditPaise }, report.indirectExpense.totalPaise)
    }

    func testGstSummaryCsvUsesSharedPaiseFormatter() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let csv = try GSTService(db: tc.db, companyId: tc.companyId).exportGSTSummaryCSV(
            fromDate: DateFormatters.parseDate("2024-08-01")!,
            toDate: DateFormatters.parseDate("2024-08-31")!
        )
        let text = String(decoding: csv, as: UTF8.self)

        XCTAssertTrue(text.contains("Period"))
        XCTAssertFalse(text.contains("/ 100.0"))
    }

    func testGstr1InvoiceExportIsInvoiceWiseAndOfflineOnly() throws {
        let tc = try makeSeededCompany()
        try tc.db.execute(
            "UPDATE avelo_accounts SET name = ? WHERE id = ?",
            [.text("=CMD|' /C calc'!A0"), .text(tc.debtorsId.uuidString)]
        )
        let posted = try VoucherService(db: tc.db, companyId: tc.companyId).post(
            draft: VoucherDraft(
                mode: .create,
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-10-01")!,
                partyAccountId: tc.debtorsId,
                narration: "Tax invoice",
                lines: [
                    .init(accountId: tc.debtorsId, amountPaise: 11800, side: .debit),
                    .init(accountId: tc.salesId, amountPaise: 10000, side: .credit),
                    .init(accountId: tc.cgstOutputId, amountPaise: 900, side: .credit),
                    .init(accountId: tc.sgstOutputId, amountPaise: 900, side: .credit)
                ]
            ),
            in: tc.fy
        ).voucher

        let gst = GSTService(db: tc.db, companyId: tc.companyId)
        let rows = try gst.gstr1InvoiceRows(
            fromDate: DateFormatters.parseDate("2024-10-01")!,
            toDate: DateFormatters.parseDate("2024-10-31")!
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.voucherId, posted.id)
        XCTAssertEqual(rows.first?.taxableValuePaise, 10000)
        XCTAssertEqual(rows.first?.cgstPaise, 900)
        XCTAssertEqual(rows.first?.sgstPaise, 900)
        XCTAssertEqual(rows.first?.invoiceValuePaise, 11800)

        let csv = String(decoding: try gst.exportGSTR1InvoiceCSV(
            fromDate: DateFormatters.parseDate("2024-10-01")!,
            toDate: DateFormatters.parseDate("2024-10-31")!
        ), as: UTF8.self)
        XCTAssertTrue(csv.contains("Invoice Number,Invoice Date,Party Name"))
        XCTAssertTrue(csv.contains(posted.number))
        XCTAssertTrue(csv.contains(",'=CMD|' /C calc'!A0,"))
        XCTAssertTrue(csv.contains("100.00,0.00,9.00,9.00,0.00,118.00"))
    }

    func testCashFlowStatementMapsIncomeAndExpenseCashMovements() throws {
        let tc = try makeSeededCompany()
        try seedActivity(tc)

        let cashFlow = try ReportService(db: tc.db, companyId: tc.companyId).cashFlow(
            fromDate: DateFormatters.parseDate("2024-04-01")!,
            toDate: DateFormatters.parseDate("2024-07-31")!
        )

        let sales = try XCTUnwrap(cashFlow.rows.first(where: { $0.accountName == "Sales" }))
        XCTAssertEqual(sales.section, .operating)
        XCTAssertEqual(sales.inflowPaise, 10000)
        XCTAssertEqual(sales.outflowPaise, 0)

        let rent = try XCTUnwrap(cashFlow.rows.first(where: { $0.accountName == "Rent Expense" }))
        XCTAssertEqual(rent.section, .operating)
        XCTAssertEqual(rent.inflowPaise, 0)
        XCTAssertEqual(rent.outflowPaise, 20000)
        XCTAssertEqual(cashFlow.operatingNetPaise, -10000)
        XCTAssertEqual(cashFlow.netCashFlowPaise, -10000)
    }

    func testStockAgeingRejectsDirectInvocationWhenInventoryIsDisabled() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(
            code: "RAW-1",
            name: "Raw Material",
            unit: "pcs"
        )
        try InventoryService(db: tc.db, companyId: tc.companyId).recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-04-01")!,
            type: .stockIn,
            quantity: 10,
            ratePaise: 250,
            notes: "Opening stock"
        )
        try tc.db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 0, inventory_link_mode = ? WHERE id = ?",
            [.text(InventoryLinkMode.manual.rawValue), .text(tc.companyId.uuidString)]
        )

        XCTAssertThrowsError(
            try ReportService(db: tc.db, companyId: tc.companyId).stockAgeing(
                asOfDate: DateFormatters.parseDate("2024-05-01")!
            )
        ) { error in
            guard case AppError.featureUnavailable = AppError.wrap(error) else {
                return XCTFail("Expected disabled inventory rejection, got \(error)")
            }
        }
    }

    // AVL-P0-033: stockValuation had no isInventoryEnabled gate at all
    // (unlike its sibling stockAgeing above), so real stock value leaked
    // into Reports and the Dashboard KPI even when disabled.
    func testStockValuationRejectsDirectInvocationWhenInventoryIsDisabled() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(
            code: "RAW-2",
            name: "Raw Material 2",
            unit: "pcs"
        )
        try InventoryService(db: tc.db, companyId: tc.companyId).recordMovement(
            itemId: item.id,
            date: DateFormatters.parseDate("2024-04-01")!,
            type: .stockIn,
            quantity: 10,
            ratePaise: 250,
            notes: "Opening stock"
        )
        try tc.db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 0, inventory_link_mode = ? WHERE id = ?",
            [.text(InventoryLinkMode.manual.rawValue), .text(tc.companyId.uuidString)]
        )

        XCTAssertThrowsError(
            try ReportService(db: tc.db, companyId: tc.companyId).stockValuation(
                asOfDate: DateFormatters.parseDate("2024-05-01")!
            )
        ) { error in
            guard case AppError.featureUnavailable = AppError.wrap(error) else {
                return XCTFail("Expected disabled inventory rejection, got \(error)")
            }
        }
    }

    func testStockValuationUsesAuthoritativeFifoCostingNotCallerStockOutRate() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "FIFO-RPT", name: "FIFO Report Item", unit: "NOS", valuationMethod: .fifo)

        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 15, ratePaise: 999)

        let report = try ReportService(db: tc.db, companyId: tc.companyId).stockValuation(
            asOfDate: DateFormatters.parseDate("2024-06-30")!
        )

        let row = try XCTUnwrap(report.rows.first(where: { $0.itemCode == "FIFO-RPT" }))
        XCTAssertEqual(row.closingQty.numerator, 5)
        XCTAssertEqual(row.closingQty.denominator, 1)
        XCTAssertEqual(row.outValuePaise, 2000)
        XCTAssertEqual(row.closingValuePaise, 1000)
        XCTAssertEqual(row.averageCostPaise, 200)
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

    func testLedgerCacheInvalidatesWhenVoucherUpdatedWithoutChangingVoucherCount() throws {
        let tc = try makeSeededCompany()
        let activity = try seedActivity(tc)
        let service = ReportService(db: tc.db, companyId: tc.companyId)
        let from = DateFormatters.parseDate("2024-04-01")!
        let to = DateFormatters.parseDate("2025-03-31")!

        let first = try service.ledger(accountId: tc.debtorsId, financialYearId: tc.fy.id, fromDate: from, toDate: to)
        XCTAssertEqual(first.periodDebitPaise, 15000)

        let changedAt = Date(timeIntervalSinceNow: 60)
        try tc.db.write { tx in
            try tx.execute(
                "UPDATE avelo_vouchers SET total_paise = ?, updated_at = ? WHERE id = ?",
                [.integer(19000), .timestamp(changedAt), .text(activity.debtorSale.id.uuidString)]
            )
            try tx.execute(
                "UPDATE trn_accounting SET amount_paise = ? WHERE voucher_id = ? AND ledger_id = ?",
                [.integer(19000), .text(activity.debtorSale.id.uuidString), .text(tc.debtorsId.uuidString)]
            )
            try tx.execute(
                "UPDATE trn_accounting SET amount_paise = ? WHERE voucher_id = ? AND ledger_id = ?",
                [.integer(19000), .text(activity.debtorSale.id.uuidString), .text(tc.salesId.uuidString)]
            )
        }

        let second = try service.ledger(accountId: tc.debtorsId, financialYearId: tc.fy.id, fromDate: from, toDate: to)
        XCTAssertEqual(second.periodDebitPaise, 19000)
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
