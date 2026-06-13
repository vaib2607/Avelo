import Foundation

public struct AccountingWorkflowsRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func deleteForVoucher(_ voucherId: Voucher.ID) throws {
        try db.execute(
            "DELETE FROM avelo_bill_allocations WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
        try db.execute(
            "DELETE FROM avelo_cheques WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
        try db.execute(
            "DELETE FROM avelo_tds_records WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
        try db.execute(
            "DELETE FROM avelo_tcs_records WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
    }

    public func workflowInputs(for voucherId: Voucher.ID) throws -> VoucherService.WorkflowInputs {
        let billAllocation = try db.queryOne(
            "SELECT kind, reference_number FROM avelo_bill_allocations WHERE voucher_id = ? LIMIT 1",
            bind: [.text(voucherId.uuidString)]
        ) { ($0.text("kind"), $0.optionalText("reference_number")) }

        let cheque = try db.queryOne(
            "SELECT cheque_number, due_date, status FROM avelo_cheques WHERE voucher_id = ? LIMIT 1",
            bind: [.text(voucherId.uuidString)]
        ) { ($0.optionalText("cheque_number"), $0.optionalDate("due_date"), $0.optionalText("status")) }

        let tds = try db.queryOne(
            "SELECT section_code, tax_paise FROM avelo_tds_records WHERE voucher_id = ? LIMIT 1",
            bind: [.text(voucherId.uuidString)]
        ) { ($0.optionalText("section_code"), $0.int("tax_paise")) }

        let tcs = try db.queryOne(
            "SELECT section_code, tax_paise FROM avelo_tcs_records WHERE voucher_id = ? LIMIT 1",
            bind: [.text(voucherId.uuidString)]
        ) { ($0.optionalText("section_code"), $0.int("tax_paise")) }

        return VoucherService.WorkflowInputs(
            billAllocationKind: billAllocation.flatMap { BillAllocationKind(rawValue: $0.0) },
            billAllocationNumber: billAllocation?.1,
            chequeNumber: cheque?.0,
            chequeDueDate: cheque?.1,
            chequeStatus: cheque?.2.flatMap { ChequeStatus(rawValue: $0) },
            tdsSectionCode: tds?.0,
            tdsTaxPaise: tds?.1,
            tcsSectionCode: tcs?.0,
            tcsTaxPaise: tcs?.1
        )
    }

    public func insert(_ a: BillAllocation) throws {
        try db.execute("INSERT INTO avelo_bill_allocations (id, company_id, voucher_id, party_account_id, kind, reference_number, allocated_paise, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                       [.text(a.id.uuidString), .text(a.companyId.uuidString), .text(a.voucherId.uuidString), .text(a.partyAccountId.uuidString), .text(a.kind.rawValue), .optionalText(a.referenceNumber), .integer(a.allocatedPaise), .timestamp(a.createdAt)])
    }
    public func insert(_ c: Cheque) throws {
        try db.execute("INSERT INTO avelo_cheques (id, company_id, voucher_id, cheque_number, bank_account_id, issue_date, due_date, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                       [.text(c.id.uuidString), .text(c.companyId.uuidString), .text(c.voucherId.uuidString), .text(c.chequeNumber), .optionalText(c.bankAccountId?.uuidString), .date(c.issueDate), .optionalDate(c.dueDate), .text(c.status.rawValue), .timestamp(c.createdAt)])
    }
    public func insert(_ r: TDSRecord) throws {
        try db.execute("INSERT INTO avelo_tds_records (id, company_id, voucher_id, section_code, base_paise, tax_paise, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       [.text(r.id.uuidString), .text(r.companyId.uuidString), .text(r.voucherId.uuidString), .text(r.sectionCode), .integer(r.basePaise), .integer(r.taxPaise), .timestamp(r.createdAt)])
    }
    public func insert(_ r: TCSRecord) throws {
        try db.execute("INSERT INTO avelo_tcs_records (id, company_id, voucher_id, section_code, base_paise, tax_paise, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       [.text(r.id.uuidString), .text(r.companyId.uuidString), .text(r.voucherId.uuidString), .text(r.sectionCode), .integer(r.basePaise), .integer(r.taxPaise), .timestamp(r.createdAt)])
    }
}
