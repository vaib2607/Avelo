import XCTest
@testable import Avelo

final class ItemInvoiceServiceTests: XCTestCase {

    func testItemInvoiceRejectsDirectPostingWhenInventoryIsDisabled() throws {
        let fx = try makeFixture()
        try fx.tc.db.execute(
            "UPDATE avelo_companies SET is_inventory_enabled = 0, inventory_link_mode = ? WHERE id = ?",
            [.text(InventoryLinkMode.manual.rawValue), .text(fx.tc.companyId.uuidString)]
        )

        XCTAssertThrowsError(
            try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
                voucherTypeCode: .sales,
                date: DateFormatters.parseDate("2024-06-01")!,
                partyAccountId: fx.customerId,
                salesOrPurchaseLedgerId: fx.tc.salesId,
                items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
                in: fx.tc.fy
            )
        ) { error in
            guard case AppError.featureUnavailable = AppError.wrap(error) else {
                return XCTFail("Expected disabled inventory rejection, got \(error)")
            }
        }
        XCTAssertEqual(
            try VoucherRepository(db: fx.tc.db).count(filter: .init(companyId: fx.tc.companyId)),
            0
        )
    }

    /// Extends `TestCompany` with the extra fixtures item-invoice posting
    /// needs: a company GSTIN, INPUT-side duty ledgers, a CESS ledger, a
    /// party with a known state, and a taxable stock item.
    private struct Fixture {
        let tc: TestCompany
        let customerId: Account.ID
        let supplierId: Account.ID
        let purchaseId: Account.ID
        let itemId: InventoryItem.ID
    }

    private func makeFixture(companyStateCode: String = "27",
                              partyGSTIN: String? = "29AAGCB7383J1Z4", // Karnataka -> inter-state vs company's MH
                              gstRateBps: Int? = 1800) throws -> Fixture {
        let tc = try TestCompany.make()

        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV" // Maharashtra ("27")
        try CompanyRepository(db: tc.db).update(company)

        let accountRepo = AccountRepository(db: tc.db)
        var customer = try XCTUnwrap(accountRepo.findById(tc.customerId))
        customer.gstin = partyGSTIN
        try accountRepo.update(customer)
        var supplier = try XCTUnwrap(accountRepo.findById(tc.supplierId))
        supplier.gstin = partyGSTIN
        try accountRepo.update(supplier)

        try accountRepo.insert(Account(companyId: tc.companyId, groupId: tc.liabilityGroupId, code: "CGST_INPUT", name: "CGST Input",
                                        openingBalancePaise: 0, openingBalanceSide: .debit))
        try accountRepo.insert(Account(companyId: tc.companyId, groupId: tc.liabilityGroupId, code: "SGST_INPUT", name: "SGST Input",
                                        openingBalancePaise: 0, openingBalanceSide: .debit))
        try accountRepo.insert(Account(companyId: tc.companyId, groupId: tc.liabilityGroupId, code: "IGST_INPUT", name: "IGST Input",
                                        openingBalancePaise: 0, openingBalanceSide: .debit))
        try accountRepo.insert(Account(companyId: tc.companyId, groupId: tc.liabilityGroupId, code: "CESS", name: "CESS",
                                        openingBalancePaise: 0, openingBalanceSide: .credit))
        let purchaseGroup = AccountGroup(companyId: tc.companyId, code: "PURCHASE_ACCOUNTS", name: "Purchase Accounts", nature: .expense)
        try AccountGroupRepository(db: tc.db).insert(purchaseGroup)
        try accountRepo.insert(Account(companyId: tc.companyId, groupId: purchaseGroup.id, code: "PURCHASE", name: "Purchase",
                                        openingBalancePaise: 0, openingBalanceSide: .debit))
        let purchase = try XCTUnwrap(accountRepo.findByCode("PURCHASE", companyId: tc.companyId))

        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "ITEM-1", name: "Widget", unit: "Nos", gstRateBps: gstRateBps)

        return Fixture(tc: tc, customerId: customer.id, supplierId: supplier.id, purchaseId: purchase.id, itemId: item.id)
    }

    // MARK: - Sales, inter-state (company MH, customer KA)

    func testSalesItemInvoicePostsIGSTForInterState() throws {
        let fx = try makeFixture()
        _ = try InventoryService(db: fx.tc.db, companyId: fx.tc.companyId).recordMovement(
            itemId: fx.itemId, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 10, ratePaise: 40_000
        )
        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)

        let result = try svc.post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: 2, ratePaise: 50_000)], // Rs 500 x 2 = Rs 1000
            in: fx.tc.fy
        )

        XCTAssertEqual(result.totalTaxableValuePaise, 100_000)
        XCTAssertEqual(result.totalIGSTPaise, 18_000)
        XCTAssertEqual(result.totalCGSTPaise, 0)
        XCTAssertEqual(result.totalSGSTPaise, 0)
        XCTAssertEqual(result.invoiceValuePaise, 118_000)

        // Ledger lines actually posted match the computed totals.
        let lines = try LedgerLineRepository(db: fx.tc.db).findForVoucher(result.voucher.id)
        let byAccount = Dictionary(uniqueKeysWithValues: lines.map { ($0.accountId, $0) })
        XCTAssertEqual(byAccount[fx.customerId]?.amountPaise, 118_000)
        XCTAssertEqual(byAccount[fx.customerId]?.side, .debit)
        XCTAssertEqual(byAccount[fx.tc.salesId]?.amountPaise, 100_000)
        XCTAssertEqual(byAccount[fx.tc.salesId]?.side, .credit)
        let igstAccount = try XCTUnwrap(AccountRepository(db: fx.tc.db).findByCode("IGST_OUTPUT", companyId: fx.tc.companyId))
        XCTAssertEqual(byAccount[igstAccount.id]?.amountPaise, 18_000)
        XCTAssertEqual(byAccount[igstAccount.id]?.side, .credit)

        // Item line audit trail persisted.
        let itemLines = try VoucherItemLineRepository(db: fx.tc.db).findForVoucher(result.voucher.id)
        XCTAssertEqual(itemLines.count, 1)
        XCTAssertEqual(itemLines[0].quantity, 2)
        XCTAssertEqual(itemLines[0].igstPaise, 18_000)

        // Stock movement recorded (company has inventory enabled).
        let movements = try InventoryRepository(db: fx.tc.db).listMovements(forVoucher: result.voucher.id)
        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movements.first?.movementType, .stockOut)
    }

    func testItemInvoiceWritesCanonicalTracksWithExactQuantityOnly() throws {
        let fx = try makeFixture()
        let inventory = InventoryService(db: fx.tc.db, companyId: fx.tc.companyId)
        _ = try inventory.recordMovement(itemId: fx.itemId, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 5, ratePaise: 10_000)
        let legacyStockBefore = try fx.tc.db.queryOne("SELECT COUNT(*) FROM avelo_stock_movements") { $0.int(0) } ?? 0
        let legacyAccountingBefore = try fx.tc.db.queryOne("SELECT COUNT(*) FROM avelo_ledger_lines") { $0.int(0) } ?? 0
        let auditFilter = AuditRepository.Filter(companyId: fx.tc.companyId)
        let auditBefore = try AuditRepository(db: fx.tc.db).list(filter: auditFilter).count

        let result = try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: try ExactQuantity.whole(2), ratePaise: 10_000)],
            in: fx.tc.fy
        )

        let evidence = try XCTUnwrap(VoucherItemLineRepository(db: fx.tc.db).findForVoucher(result.voucher.id).first)
        XCTAssertEqual(evidence.exactQuantity, try ExactQuantity.whole(2))
        let inventoryRows = try InventoryRepository(db: fx.tc.db).listMovements(forVoucher: result.voucher.id)
        XCTAssertEqual(inventoryRows.first?.quantity, try ExactQuantity.whole(2))
        XCTAssertEqual(try fx.tc.db.queryOne("SELECT COUNT(*) FROM avelo_stock_movements") { $0.int(0) } ?? 0, legacyStockBefore)
        XCTAssertEqual(try fx.tc.db.queryOne("SELECT COUNT(*) FROM avelo_ledger_lines") { $0.int(0) } ?? 0, legacyAccountingBefore)
        let newAudit = try AuditRepository(db: fx.tc.db).list(filter: auditFilter)
        XCTAssertEqual(newAudit.count, auditBefore + 1)
        XCTAssertEqual(newAudit.first(where: { $0.entityId == result.voucher.id.uuidString })?.entityType, "item_invoice")
    }

    func testItemInvoiceRejectsFractionalQuantityUntilGSTSupportsIt() throws {
        let fx = try makeFixture()
        let quantity = try ExactQuantity(numerator: 3, denominator: 2)

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: quantity, ratePaise: 10_000)],
            in: fx.tc.fy
        )) { error in
            guard case .validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected typed validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .itemInvoiceQuantityUnsupported)
        }
    }

    func testItemInvoiceRejectsInactiveItemWithTypedError() throws {
        let fx = try makeFixture()
        try InventoryRepository(db: fx.tc.db).disableItem(fx.itemId)

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        )) { error in
            guard case .validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected typed validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .inventoryItemUnavailable)
        }
    }

    func testItemInvoiceRejectsUnavailableMainLocationWithTypedError() throws {
        let fx = try makeFixture()
        try fx.tc.db.execute(
            "UPDATE avelo_inventory_locations SET is_active = 0 WHERE company_id = ? AND code = 'MAIN'",
            [.text(fx.tc.companyId.uuidString)]
        )

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        )) { error in
            guard case .validation(let validation) = AppError.wrap(error) else {
                return XCTFail("Expected typed validation error, got \(error)")
            }
            XCTAssertEqual(validation.code, .inventoryLocationUnavailable)
        }
    }

    /// Phase 1.4 staged-rollback matrix: a failure discovered at the
    /// inventory stage (unavailable main location, past header/accounting
    /// construction in the canonical posting order) must leave zero rows in
    /// every canonical/legacy table it would have touched — proving the
    /// "one outer re-entrant transaction" claim empirically, not just
    /// architecturally. Existing coverage only asserted the thrown error
    /// type, never the absence of a partial write.
    func testInventoryStageFailureLeavesNoPartialWriteAcrossAnyTable() throws {
        let fx = try makeFixture()
        try fx.tc.db.execute(
            "UPDATE avelo_inventory_locations SET is_active = 0 WHERE company_id = ? AND code = 'MAIN'",
            [.text(fx.tc.companyId.uuidString)]
        )

        let tables = ["avelo_vouchers", "trn_accounting", "trn_inventory", "trn_inventory_cost_allocations", "avelo_audit_events"]
        func counts() throws -> [String: Int64] {
            var result: [String: Int64] = [:]
            for table in tables {
                result[table] = try fx.tc.db.queryOne(
                    "SELECT COUNT(*) FROM \(table) WHERE company_id = ?", bind: [.text(fx.tc.companyId.uuidString)]
                ) { $0.int(0) } ?? -1
            }
            return result
        }
        // Fixture setup (account creation, company GSTIN update) legitimately
        // writes its own audit events before this attempt — baseline before
        // the failed post, not an absolute zero, is the correct invariant.
        let before = try counts()

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        ))

        let after = try counts()
        for table in tables {
            XCTAssertEqual(after[table], before[table], "\(table) row count must be unchanged after a failed post — no partial write")
        }
    }

    /// Phase 1.4 staged-rollback matrix: a failure discovered at the
    /// validation stage (before the transaction even opens) must leave zero
    /// rows changed — the trivial case, but still worth asserting explicitly
    /// alongside its mid-transaction siblings rather than only checking the
    /// thrown error type.
    func testValidationStageFailureLeavesNoPartialWriteAcrossAnyTable() throws {
        let fx = try makeFixture()
        try InventoryRepository(db: fx.tc.db).disableItem(fx.itemId)

        let tables = ["avelo_vouchers", "trn_accounting", "trn_inventory", "trn_inventory_cost_allocations", "avelo_audit_events"]
        func counts() throws -> [String: Int64] {
            var result: [String: Int64] = [:]
            for table in tables {
                result[table] = try fx.tc.db.queryOne(
                    "SELECT COUNT(*) FROM \(table) WHERE company_id = ?", bind: [.text(fx.tc.companyId.uuidString)]
                ) { $0.int(0) } ?? -1
            }
            return result
        }
        let before = try counts()

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        ))

        let after = try counts()
        for table in tables {
            XCTAssertEqual(after[table], before[table], "\(table) row count must be unchanged after a validation-stage failure")
        }
    }

    /// Phase 1.4 staged-rollback matrix: a failure discovered at the
    /// accounting stage — after the transaction opens and the voucher header
    /// is constructed, but while `trn_accounting` rows are being written —
    /// must roll back the header too. `validateCurrentPostingState` already
    /// pre-checks FY-lock before the transaction opens, so a real
    /// mid-transaction failure needs a DB-layer trigger the pre-checks can't
    /// see. Same injected-trigger technique as
    /// `InventoryCostAllocationServiceTests
    /// .testAuditFailureRollsBackAllocationAndLandedValue`.
    func testAccountingStageFailureLeavesNoPartialWriteAcrossAnyTable() throws {
        let fx = try makeFixture()
        try fx.tc.db.execute(
            "CREATE TRIGGER test_reject_accounting_insert BEFORE INSERT ON trn_accounting BEGIN SELECT RAISE(ABORT, 'forced accounting stage failure'); END;"
        )

        let tables = ["avelo_vouchers", "trn_accounting", "trn_inventory", "trn_inventory_cost_allocations", "avelo_audit_events"]
        func counts() throws -> [String: Int64] {
            var result: [String: Int64] = [:]
            for table in tables {
                result[table] = try fx.tc.db.queryOne(
                    "SELECT COUNT(*) FROM \(table) WHERE company_id = ?", bind: [.text(fx.tc.companyId.uuidString)]
                ) { $0.int(0) } ?? -1
            }
            return result
        }
        let before = try counts()

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        ))

        let after = try counts()
        for table in tables {
            XCTAssertEqual(after[table], before[table], "\(table) row count must be unchanged after an accounting-stage failure — including the voucher header")
        }
    }

    /// Phase 1.4 staged-rollback matrix: a failure discovered at the final
    /// audit-write stage — the last step of the outer transaction, after
    /// header/accounting/item-lines/inventory are all constructed — must
    /// still roll back every prior write in the same transaction, not just
    /// the audit table.
    func testAuditWriteStageFailureLeavesNoPartialWriteAcrossAnyTable() throws {
        let fx = try makeFixture()
        try fx.tc.db.execute(
            "CREATE TRIGGER test_reject_item_invoice_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'voucherPosted' AND NEW.entity_type = 'item_invoice' BEGIN SELECT RAISE(ABORT, 'forced audit stage failure'); END;"
        )

        let tables = ["avelo_vouchers", "trn_accounting", "trn_inventory", "trn_inventory_cost_allocations", "avelo_audit_events"]
        func counts() throws -> [String: Int64] {
            var result: [String: Int64] = [:]
            for table in tables {
                result[table] = try fx.tc.db.queryOne(
                    "SELECT COUNT(*) FROM \(table) WHERE company_id = ?", bind: [.text(fx.tc.companyId.uuidString)]
                ) { $0.int(0) } ?? -1
            }
            return result
        }
        let before = try counts()

        XCTAssertThrowsError(try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        ))

        let after = try counts()
        for table in tables {
            XCTAssertEqual(after[table], before[table], "\(table) row count must be unchanged after an audit-write-stage failure — header/accounting/inventory must all roll back")
        }
    }

    // MARK: - Purchase, intra-state (company MH, party also MH)

    func testPurchaseItemInvoiceSplitsCGSTSGSTForIntraState() throws {
        let fx = try makeFixture(partyGSTIN: "27AAGCB7383J1Z4") // Maharashtra, same as company

        let accountRepo = AccountRepository(db: fx.tc.db)
        var vendor = try XCTUnwrap(accountRepo.findById(fx.supplierId))
        vendor.gstin = "27AAGCB7383J1Z4"
        try accountRepo.update(vendor)

        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)
        let result = try svc.post(
            voucherTypeCode: .purchase,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId,
            salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 3, ratePaise: 100_000)], // Rs 1000 x 3 = Rs 3000
            in: fx.tc.fy
        )

        XCTAssertEqual(result.totalTaxableValuePaise, 300_000)
        XCTAssertEqual(result.totalCGSTPaise, 27_000) // 9% of 300000
        XCTAssertEqual(result.totalSGSTPaise, 27_000)
        XCTAssertEqual(result.totalIGSTPaise, 0)
        XCTAssertEqual(result.invoiceValuePaise, 354_000)

        let lines = try LedgerLineRepository(db: fx.tc.db).findForVoucher(result.voucher.id)
        let byAccount = Dictionary(uniqueKeysWithValues: lines.map { ($0.accountId, $0) })
        // Vendor is credited (we owe them); Purchase + CGST/SGST Input are debited.
        XCTAssertEqual(byAccount[fx.supplierId]?.side, .credit)
        XCTAssertEqual(byAccount[fx.supplierId]?.amountPaise, 354_000)
        XCTAssertEqual(byAccount[fx.purchaseId]?.side, .debit)
        XCTAssertEqual(byAccount[fx.purchaseId]?.amountPaise, 300_000)
        let cgstInput = try XCTUnwrap(accountRepo.findByCode("CGST_INPUT", companyId: fx.tc.companyId))
        XCTAssertEqual(byAccount[cgstInput.id]?.side, .debit)
        XCTAssertEqual(byAccount[cgstInput.id]?.amountPaise, 27_000)

        // Purchase increases stock, valued at the purchase rate.
        let movements = try InventoryRepository(db: fx.tc.db).listMovements(forVoucher: result.voucher.id)
        let posted = try XCTUnwrap(movements.first)
        XCTAssertEqual(posted.movementType, .stockIn)
        XCTAssertEqual(posted.totalValuePaise, 300_000)
    }

    // MARK: - Non-taxable item

    func testExemptItemProducesNoDutyLines() throws {
        let fx = try makeFixture(gstRateBps: nil)
        let inventory = InventoryService(db: fx.tc.db, companyId: fx.tc.companyId)
        var item = try XCTUnwrap(InventoryRepository(db: fx.tc.db).findItemById(fx.itemId))
        item.gstTaxability = .exempt
        try inventory.updateItem(item)
        _ = try inventory.recordMovement(
            itemId: fx.itemId, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 5, ratePaise: 8_000
        )

        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)
        let result = try svc.post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        )

        XCTAssertEqual(result.totalIGSTPaise, 0)
        XCTAssertEqual(result.totalCGSTPaise, 0)
        XCTAssertEqual(result.invoiceValuePaise, 10_000)
        let lines = try LedgerLineRepository(db: fx.tc.db).findForVoucher(result.voucher.id)
        XCTAssertEqual(lines.count, 2) // just customer + sales, no duty lines
    }

    // MARK: - Failure modes

    func testThrowsWhenPartyStateUnknown() throws {
        let fx = try makeFixture(partyGSTIN: nil)
        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)

        XCTAssertThrowsError(try svc.post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        )) { error in
            guard case AppError.businessRule(let message) = error else { return XCTFail("Expected businessRule, got \(error)") }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("party"))
        }
    }

    func testThrowsWithNoItems() throws {
        let fx = try makeFixture()
        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)

        XCTAssertThrowsError(try svc.post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [],
            in: fx.tc.fy
        ))
    }

    /// Regression for the item-invoice atomicity fix: a stock-movement
    /// failure (selling more than is on hand) must roll back the ledger
    /// voucher too, not leave a posted voucher with no stock movement.
    func testStockMovementFailureRollsBackVoucherPosting() throws {
        let fx = try makeFixture()
        // No stock-in performed — any sale exceeds the on-hand quantity (0).
        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)

        XCTAssertThrowsError(try svc.post(
            voucherTypeCode: .sales,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: 5, ratePaise: 50_000)],
            in: fx.tc.fy
        )) { error in
            guard case AppError.validation = error else { return XCTFail("Expected validation error, got \(error)") }
        }

        let voucherCount = try VoucherRepository(db: fx.tc.db).count(
            filter: .init(companyId: fx.tc.companyId, voucherTypeCodes: [.sales])
        )
        XCTAssertEqual(voucherCount, 0, "Voucher posting must roll back when the stock movement fails")
    }

    func testThrowsForNonSalesPurchaseVoucherType() throws {
        let fx = try makeFixture()
        let svc = ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId)

        XCTAssertThrowsError(try svc.post(
            voucherTypeCode: .journal,
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.customerId,
            salesOrPurchaseLedgerId: fx.tc.salesId,
            items: [.init(itemId: fx.itemId, quantity: 1, ratePaise: 10_000)],
            in: fx.tc.fy
        )) { error in
            guard case AppError.businessRule = error else { return XCTFail("Expected businessRule, got \(error)") }
        }
    }

    func testPurchasePartialReturnPostsDebitNoteAndHonorsLockedFY() throws {
        let fx = try makeFixture(partyGSTIN: "27AAGCB7383J1Z4")
        let purchase = try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase, date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId, salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 4, ratePaise: 10_000)], narration: "purchase", in: fx.tc.fy
        )
        let source = try XCTUnwrap(InventoryRepository(db: fx.tc.db).listMovements(forVoucher: purchase.voucher.id).first)
        let draft = VoucherDraft(
            mode: .create, entryMode: .itemInvoice, voucherTypeCode: .debitNote,
            date: DateFormatters.parseDate("2024-06-02")!, partyAccountId: fx.supplierId, narration: "return",
            lines: [
                .init(accountId: fx.supplierId, amountPaise: 20_000, side: .debit, lineOrder: 0),
                .init(accountId: fx.purchaseId, amountPaise: 20_000, side: .credit, lineOrder: 1)
            ]
        )
        let service = ItemInvoiceReturnService(db: fx.tc.db, companyId: fx.tc.companyId)
        let returned = try service.post(.init(draft: draft, financialYear: fx.tc.fy, lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(2))], reason: "damaged"))
        XCTAssertEqual(returned.voucher.voucherTypeCode, .debitNote)
        XCTAssertEqual(returned.movements.first?.movementType, .stockOut)
        try FinancialYearRepository(db: fx.tc.db).lock(fx.tc.fy.id)
        XCTAssertThrowsError(try service.post(.init(draft: draft, financialYear: fx.tc.fy, lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(1))], reason: "locked")))
    }

    /// Phase §4.6/§4.7 reversal parity: `ItemInvoiceService.reverse` flips
    /// ledger lines and posts opposite-direction stock movements — this
    /// proves that raw SQL over the canonical tracks agrees the original
    /// plus its reversal nets to zero, rather than only checking the
    /// reversal's own type/status fields.
    func testItemInvoiceReversalNetsCanonicalTracksToZero() throws {
        let fx = try makeFixture(partyGSTIN: "27AAGCB7383J1Z4") // intra-state, no duty-account variance to reason about
        let posted = try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).post(
            voucherTypeCode: .purchase, date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: fx.supplierId, salesOrPurchaseLedgerId: fx.purchaseId,
            items: [.init(itemId: fx.itemId, quantity: 4, ratePaise: 10_000)], narration: "purchase", in: fx.tc.fy
        )

        _ = try ItemInvoiceService(db: fx.tc.db, companyId: fx.tc.companyId).reverse(posted.voucher.id, reason: "test reversal")

        // Accounting: every ledger account touched by the original and its
        // reversal must net to zero paise across debit/credit.
        let accountingNetRows: [(String, Int64)] = try fx.tc.db.query(
            """
            SELECT ledger_id, SUM(CASE WHEN debit_or_credit = 'debit' THEN amount_paise ELSE -amount_paise END)
            FROM trn_accounting
            WHERE company_id = ? AND voucher_id IN (?, (SELECT id FROM avelo_vouchers WHERE reversal_of_id = ?))
            GROUP BY ledger_id
            """,
            bind: [.text(fx.tc.companyId.uuidString), .text(posted.voucher.id.uuidString), .text(posted.voucher.id.uuidString)]
        ) { row in (try row.requiredText("ledger_id"), row.int(1)) }
        for (ledgerId, net) in accountingNetRows {
            XCTAssertEqual(net, 0, "Ledger \(ledgerId) must net to zero paise across the original and its reversal")
        }

        // Inventory: net signed quantity across the original stock-in and
        // its reversal stock-out must be zero for the item touched.
        let netQuantity = try XCTUnwrap(fx.tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity_numerator ELSE -quantity_numerator END), 0)
            FROM trn_inventory
            WHERE company_id = ? AND stock_item_id = ?
            """,
            bind: [.text(fx.tc.companyId.uuidString), .text(fx.itemId.uuidString)]
        ) { $0.int(0) })
        XCTAssertEqual(netQuantity, 0, "Net stock quantity must be zero after reversal")
    }
}
