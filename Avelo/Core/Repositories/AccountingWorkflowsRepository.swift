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
    }

    public func workflowInputs(for voucherId: Voucher.ID) throws -> VoucherService.WorkflowInputs {
        var workflow = VoucherService.WorkflowInputs()
        if let allocation = try findBillAllocation(for: voucherId) {
            workflow.billAllocationKind = allocation.kind
            workflow.billAllocationNumber = allocation.referenceNumber
        }
        if let cheque = try findCheque(for: voucherId) {
            workflow.chequeNumber = cheque.chequeNumber
            workflow.chequeDueDate = cheque.dueDate
            workflow.chequeStatus = cheque.status
        }
        return workflow
    }

    public func insert(_ a: BillAllocation) throws {
        try db.execute(
            """
            INSERT INTO avelo_bill_allocations
            (id, company_id, voucher_id, party_account_id, kind, reference_number, allocated_paise, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(a.id.uuidString),
                .text(a.companyId.uuidString),
                .text(a.voucherId.uuidString),
                .text(a.partyAccountId.uuidString),
                .text(a.kind.rawValue),
                .optionalText(a.referenceNumber),
                .integer(a.allocatedPaise),
                .timestamp(a.createdAt)
            ]
        )
    }

    public func insert(_ c: Cheque) throws {
        try db.execute(
            """
            INSERT INTO avelo_cheques
            (id, company_id, voucher_id, cheque_number, issue_date, due_date, status, bounced_reversal_voucher_id, represented_from_cheque_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(c.id.uuidString),
                .text(c.companyId.uuidString),
                .text(c.voucherId.uuidString),
                .text(c.chequeNumber),
                .date(c.issueDate),
                .optionalDate(c.dueDate),
                .text(c.status.rawValue),
                .optionalText(c.bouncedReversalVoucherId?.uuidString),
                .optionalText(c.representedFromChequeId?.uuidString),
                .timestamp(c.createdAt)
            ]
        )
    }

    public func update(_ c: Cheque) throws {
        try db.execute(
            """
            UPDATE avelo_cheques SET
                cheque_number = ?,
                issue_date = ?,
                due_date = ?,
                status = ?,
                bounced_reversal_voucher_id = ?,
                represented_from_cheque_id = ?
            WHERE id = ?
            """,
            [
                .text(c.chequeNumber),
                .date(c.issueDate),
                .optionalDate(c.dueDate),
                .text(c.status.rawValue),
                .optionalText(c.bouncedReversalVoucherId?.uuidString),
                .optionalText(c.representedFromChequeId?.uuidString),
                .text(c.id.uuidString)
            ]
        )
    }

    public func insert(_ r: TDSRecord) throws {
        _ = r
        throw AppError.featureUnavailable("TDS workflows are deferred outside the frozen schema.")
    }

    public func insert(_ r: TCSRecord) throws {
        _ = r
        throw AppError.featureUnavailable("TCS workflows are deferred outside the frozen schema.")
    }

    public func findCheque(for voucherId: Voucher.ID) throws -> Cheque? {
        try db.queryOne(
            """
            SELECT id, company_id, voucher_id, cheque_number, issue_date, due_date, status, bounced_reversal_voucher_id, represented_from_cheque_id, created_at
            FROM avelo_cheques
            WHERE voucher_id = ?
            LIMIT 1
            """,
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToCheque($0) }
    }

    public func findRepresentedCheque(from chequeId: Cheque.ID) throws -> Cheque? {
        try db.queryOne(
            """
            SELECT id, company_id, voucher_id, cheque_number, issue_date, due_date, status, bounced_reversal_voucher_id, represented_from_cheque_id, created_at
            FROM avelo_cheques
            WHERE represented_from_cheque_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            bind: [.text(chequeId.uuidString)]
        ) { try Self.rowToCheque($0) }
    }

    public struct ChequeRegisterRow: Identifiable, Sendable {
        public let cheque: Cheque
        public let voucherNumber: String
        public let partyName: String
        public let amountPaise: Int64
        public var id: Cheque.ID { cheque.id }
    }

    public func listCheques(companyId: Company.ID, status: ChequeStatus? = nil) throws -> [ChequeRegisterRow] {
        var sql = """
            SELECT c.id, c.company_id, c.voucher_id, c.cheque_number, c.issue_date, c.due_date, c.status,
                   c.bounced_reversal_voucher_id, c.represented_from_cheque_id, c.created_at,
                   v.number AS voucher_number, v.total_paise,
                   COALESCE(party.name, '') AS party_name
            FROM avelo_cheques c
            JOIN avelo_vouchers v ON v.id = c.voucher_id AND v.company_id = c.company_id
            LEFT JOIN avelo_accounts party ON party.id = v.party_account_id AND party.company_id = c.company_id
            WHERE c.company_id = ?
        """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        if let status {
            sql += " AND c.status = ?"
            bind.append(.text(status.rawValue))
        }
        sql += " ORDER BY c.due_date IS NULL, c.due_date, c.issue_date DESC"
        return try db.query(sql, bind: bind) { row in
            ChequeRegisterRow(
                cheque: try Self.rowToCheque(row),
                voucherNumber: try row.requiredText("voucher_number"),
                partyName: try row.requiredText("party_name"),
                amountPaise: try row.requiredInt("total_paise")
            )
        }
    }

    public func findBillAllocation(for voucherId: Voucher.ID) throws -> BillAllocation? {
        try db.queryOne(
            """
            SELECT id, company_id, voucher_id, party_account_id, kind, reference_number, allocated_paise, created_at
            FROM avelo_bill_allocations
            WHERE voucher_id = ?
            ORDER BY created_at ASC, id ASC
            LIMIT 1
            """,
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToBillAllocation($0) }
    }

    public func listBillAllocations(companyId: Company.ID,
                                    asOfDate: Date? = nil,
                                    partyAccountId: Account.ID? = nil) throws -> [BillAllocation] {
        var sql = """
            SELECT id, company_id, voucher_id, party_account_id, kind, reference_number, allocated_paise, created_at
            FROM avelo_bill_allocations
            WHERE company_id = ?
            """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        if let partyAccountId {
            sql += " AND party_account_id = ?"
            bind.append(.text(partyAccountId.uuidString))
        }
        if let asOfDate {
            sql += """
                 AND voucher_id IN (
                    SELECT id FROM avelo_vouchers
                    WHERE company_id = ? AND date <= ?
                 )
                 """
            bind.append(.text(companyId.uuidString))
            bind.append(.date(asOfDate))
        }
        sql += " ORDER BY created_at ASC, id ASC"
        return try db.query(sql, bind: bind) { try Self.rowToBillAllocation($0) }
    }

    private static func rowToBillAllocation(_ row: Row) throws -> BillAllocation {
        BillAllocation(
            id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_bill_allocations.id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_bill_allocations.company_id"),
            voucherId: try UUIDParsing.required(row.requiredText("voucher_id"), field: "avelo_bill_allocations.voucher_id"),
            partyAccountId: try UUIDParsing.required(row.requiredText("party_account_id"), field: "avelo_bill_allocations.party_account_id"),
            kind: try row.enumValue("kind"),
            referenceNumber: try row.checkedOptionalText("reference_number"),
            allocatedPaise: try row.requiredInt("allocated_paise"),
            createdAt: try row.timestamp("created_at")
        )
    }

    private static func rowToCheque(_ row: Row) throws -> Cheque {
        Cheque(
            id: try UUIDParsing.required(row.requiredText("id"), field: "avelo_cheques.id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_cheques.company_id"),
            voucherId: try UUIDParsing.required(row.requiredText("voucher_id"), field: "avelo_cheques.voucher_id"),
            chequeNumber: try row.requiredText("cheque_number"),
            issueDate: try row.requiredDate("issue_date"),
            dueDate: try row.optionalDate("due_date"),
            status: try row.enumValue("status"),
            bouncedReversalVoucherId: try UUIDParsing.optional(try row.checkedOptionalText("bounced_reversal_voucher_id"), field: "avelo_cheques.bounced_reversal_voucher_id"),
            representedFromChequeId: try UUIDParsing.optional(try row.checkedOptionalText("represented_from_cheque_id"), field: "avelo_cheques.represented_from_cheque_id"),
            createdAt: try row.timestamp("created_at")
        )
    }
}
