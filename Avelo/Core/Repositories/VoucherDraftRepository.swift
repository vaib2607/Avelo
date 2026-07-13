import Foundation

/// Persistence for autosaved, in-progress voucher entries (AVL-P0-018).
/// Deliberately outside the double-entry/audit-trail model: these rows are
/// never validated, never referenced by reports, and exist only to recover
/// unsaved keystrokes after a crash or quit.
public struct VoucherDraftRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func upsert(_ entry: VoucherEntryDraft) throws {
        try db.execute(
            """
            INSERT INTO avelo_voucher_drafts
            (id, company_id, voucher_type_code, date, party_account_id, narration,
             bill_reference_type, bill_reference_number, cheque_number, cheque_due_date,
             account_ledger_id, lines_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                voucher_type_code = excluded.voucher_type_code,
                date = excluded.date,
                party_account_id = excluded.party_account_id,
                narration = excluded.narration,
                bill_reference_type = excluded.bill_reference_type,
                bill_reference_number = excluded.bill_reference_number,
                cheque_number = excluded.cheque_number,
                cheque_due_date = excluded.cheque_due_date,
                account_ledger_id = excluded.account_ledger_id,
                lines_json = excluded.lines_json,
                updated_at = excluded.updated_at
            """,
            [
                .text(entry.id.uuidString),
                .text(entry.companyId.uuidString),
                .text(entry.voucherTypeCode.rawValue),
                .timestamp(entry.date),
                .optionalText(entry.partyAccountId?.uuidString),
                .text(entry.narration),
                .optionalText(entry.billReferenceType?.rawValue),
                .optionalText(entry.billReferenceNumber),
                .optionalText(entry.chequeNumber),
                .optionalTimestamp(entry.chequeDueDate),
                .optionalText(entry.accountLedgerId?.uuidString),
                .text(entry.linesJSON),
                .timestamp(entry.updatedAt)
            ]
        )
    }

    /// The single most-recently-updated draft for a company, if any. Only one
    /// "new voucher" sheet can be open at a time, but drafts from more than
    /// one abandoned session can accumulate; recovery only ever offers the
    /// latest one.
    public func mostRecent(companyId: Company.ID) throws -> VoucherEntryDraft? {
        try db.queryOne(
            """
            SELECT id, company_id, voucher_type_code, date, party_account_id, narration,
                   bill_reference_type, bill_reference_number, cheque_number, cheque_due_date,
                   account_ledger_id, lines_json, updated_at
            FROM avelo_voucher_drafts
            WHERE company_id = ?
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            bind: [.text(companyId.uuidString)],
            row: decode
        )
    }

    public func delete(id: VoucherEntryDraft.ID) throws {
        try db.execute("DELETE FROM avelo_voucher_drafts WHERE id = ?", [.text(id.uuidString)])
    }

    public func deleteAll(companyId: Company.ID) throws {
        try db.execute("DELETE FROM avelo_voucher_drafts WHERE company_id = ?", [.text(companyId.uuidString)])
    }

    private func decode(_ r: Row) throws -> VoucherEntryDraft {
        VoucherEntryDraft(
            id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_voucher_drafts.id"),
            companyId: try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_voucher_drafts.company_id"),
            voucherTypeCode: try r.enumValue("voucher_type_code"),
            date: try r.timestamp("date"),
            partyAccountId: try UUIDParsing.optional(try r.checkedOptionalText("party_account_id"), field: "avelo_voucher_drafts.party_account_id"),
            narration: try r.requiredText("narration"),
            billReferenceType: try r.optionalEnumValue("bill_reference_type"),
            billReferenceNumber: try r.checkedOptionalText("bill_reference_number"),
            chequeNumber: try r.checkedOptionalText("cheque_number"),
            chequeDueDate: try r.optionalTimestamp("cheque_due_date"),
            accountLedgerId: try UUIDParsing.optional(try r.checkedOptionalText("account_ledger_id"), field: "avelo_voucher_drafts.account_ledger_id"),
            linesJSON: try r.requiredText("lines_json"),
            updatedAt: try r.timestamp("updated_at")
        )
    }
}
