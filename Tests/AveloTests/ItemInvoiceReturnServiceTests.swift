import XCTest
@testable import Avelo

final class ItemInvoiceReturnServiceTests: XCTestCase {
    func testSalesPartialReturnPostsCreditNoteAndRejectsOverReturn() throws {
        let tc = try TestCompany.make()
        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV"
        try CompanyRepository(db: tc.db).update(company)
        var customer = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId))
        customer.gstin = "29AAGCB7383J1Z4"
        try AccountRepository(db: tc.db).update(customer)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "RET-1", name: "Return Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        let sale = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).post(
            voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: tc.customerId, salesOrPurchaseLedgerId: tc.salesId,
            items: [.init(itemId: item.id, quantity: 4, ratePaise: 100)], narration: "sale", in: tc.fy
        )
        let source = try XCTUnwrap(InventoryRepository(db: tc.db).listMovements(forVoucher: sale.voucher.id).first)
        let draft = VoucherDraft(
            mode: .create, entryMode: .itemInvoice, voucherTypeCode: .creditNote,
            date: DateFormatters.parseDate("2024-06-02")!, partyAccountId: tc.customerId, narration: "returned",
            lines: [
                .init(accountId: tc.customerId, amountPaise: 200, side: .credit, lineOrder: 0),
                .init(accountId: tc.salesId, amountPaise: 200, side: .debit, lineOrder: 1)
            ]
        )
        let service = ItemInvoiceReturnService(db: tc.db, companyId: tc.companyId)
        let first = try service.post(.init(draft: draft, financialYear: tc.fy, lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(2))], reason: "customer return"))
        XCTAssertEqual(first.voucher.voucherTypeCode, .creditNote)
        XCTAssertEqual(first.movements.first?.movementType, .stockIn)
        XCTAssertEqual(first.movements.first?.reversedMovementId, source.id)
        XCTAssertThrowsError(try service.post(.init(draft: draft, financialYear: tc.fy, lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(3))], reason: "too many")))
    }

    func testItemInvoiceReverseWritesOppositeCanonicalTracks() throws {
        let tc = try TestCompany.make()
        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV"
        try CompanyRepository(db: tc.db).update(company)
        var customer = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId))
        customer.gstin = "29AAGCB7383J1Z4"
        try AccountRepository(db: tc.db).update(customer)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "REV-1", name: "Reverse Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 4, ratePaise: 100)
        let sale = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).post(voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!, partyAccountId: tc.customerId, salesOrPurchaseLedgerId: tc.salesId, items: [.init(itemId: item.id, quantity: 2, ratePaise: 100)], narration: "sale", in: tc.fy)
        let reversed = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).reverse(sale.voucher.id, reason: "mistake")
        XCTAssertTrue(reversed.isReversal)
        XCTAssertEqual(try VoucherItemLineRepository(db: tc.db).findForVoucher(reversed.id).count, 1)
        XCTAssertEqual(try InventoryRepository(db: tc.db).listMovements(forVoucher: reversed.id).first?.movementType, .stockIn)
    }

    func testItemInvoiceCancelCreatesCompositeReversalAndMarksOriginal() throws {
        let tc = try TestCompany.make()
        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV"
        try CompanyRepository(db: tc.db).update(company)
        var customer = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId))
        customer.gstin = "29AAGCB7383J1Z4"
        try AccountRepository(db: tc.db).update(customer)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "CAN-1", name: "Cancel Item", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 4, ratePaise: 100)
        let sale = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).post(voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!, partyAccountId: tc.customerId, salesOrPurchaseLedgerId: tc.salesId, items: [.init(itemId: item.id, quantity: 2, ratePaise: 100)], narration: "sale", in: tc.fy)
        let cancelled = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).cancel(sale.voucher.id, reason: "void")
        XCTAssertEqual(cancelled.status, .cancelled)
        let reversalId = try XCTUnwrap(cancelled.cancellationVoucherId)
        XCTAssertEqual(try InventoryRepository(db: tc.db).listMovements(forVoucher: reversalId).count, 1)
    }

    func testPartialReturnRejectsForeignCompanySourceBeforeWriting() throws {
        let primary = try TestCompany.make()
        let other = try TestCompany.seed(into: primary.db, companyId: UUID(), companyName: "Other")
        let item = try InventoryService(db: primary.db, companyId: other.companyId).createItem(code: "FOREIGN", name: "Foreign", unit: "NOS")
        _ = try InventoryService(db: primary.db, companyId: other.companyId).recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 1, ratePaise: 100)
        let foreign = try XCTUnwrap(InventoryRepository(db: primary.db).listMovementsChronologically(companyId: other.companyId, itemId: item.id).first)
        let draft = VoucherDraft(mode: .create, entryMode: .itemInvoice, voucherTypeCode: .debitNote, date: DateFormatters.parseDate("2024-06-02")!, partyAccountId: primary.supplierId, narration: "bad", lines: [
            .init(accountId: primary.supplierId, amountPaise: 100, side: .debit, lineOrder: 0),
            .init(accountId: primary.salesId, amountPaise: 100, side: .credit, lineOrder: 1)
        ])
        XCTAssertThrowsError(try ItemInvoiceReturnService(db: primary.db, companyId: primary.companyId).post(.init(draft: draft, financialYear: primary.fy, lines: [.init(sourceInventoryId: foreign.id, quantity: try ExactQuantity.whole(1))], reason: "bad")))
    }

    func testReturnAuditFailureRollsBackCompositeRows() throws {
        let tc = try TestCompany.make()
        var company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(tc.companyId))
        company.gstin = "27AAPFU0939F1ZV"
        try CompanyRepository(db: tc.db).update(company)
        var customer = try XCTUnwrap(AccountRepository(db: tc.db).findById(tc.customerId))
        customer.gstin = "29AAGCB7383J1Z4"
        try AccountRepository(db: tc.db).update(customer)
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "RET-ROLL", name: "Return rollback", unit: "NOS")
        _ = try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-01")!, type: .stockIn, quantity: 4, ratePaise: 100)
        let sale = try ItemInvoiceService(db: tc.db, companyId: tc.companyId).post(voucherTypeCode: .sales, date: DateFormatters.parseDate("2024-06-01")!, partyAccountId: tc.customerId, salesOrPurchaseLedgerId: tc.salesId, items: [.init(itemId: item.id, quantity: 2, ratePaise: 100)], narration: "sale", in: tc.fy)
        let source = try XCTUnwrap(InventoryRepository(db: tc.db).listMovements(forVoucher: sale.voucher.id).first)
        let vouchersBefore = try VoucherRepository(db: tc.db).count(filter: .init(companyId: tc.companyId))
        let movementsBefore = try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id).count
        try tc.db.execute("CREATE TRIGGER test_reject_return_audit BEFORE INSERT ON avelo_audit_events WHEN NEW.action = 'itemInvoiceReturnPosted' BEGIN SELECT RAISE(ABORT, 'forced return audit failure'); END;")
        let draft = VoucherDraft(mode: .create, entryMode: .itemInvoice, voucherTypeCode: .creditNote, date: DateFormatters.parseDate("2024-06-02")!, partyAccountId: tc.customerId, narration: "return", lines: [
            .init(accountId: tc.customerId, amountPaise: 100, side: .credit, lineOrder: 0),
            .init(accountId: tc.salesId, amountPaise: 100, side: .debit, lineOrder: 1)
        ])

        XCTAssertThrowsError(try ItemInvoiceReturnService(db: tc.db, companyId: tc.companyId).post(.init(draft: draft, financialYear: tc.fy, lines: [.init(sourceInventoryId: source.id, quantity: try ExactQuantity.whole(1))], reason: "return")))
        XCTAssertEqual(try VoucherRepository(db: tc.db).count(filter: .init(companyId: tc.companyId)), vouchersBefore)
        XCTAssertEqual(try InventoryRepository(db: tc.db).listMovementsChronologically(companyId: tc.companyId, itemId: item.id).count, movementsBefore)
    }
}
