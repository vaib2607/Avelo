import Foundation

public struct AccountingWorkflowsRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

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
