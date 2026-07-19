import Foundation

/// An autosaved, in-progress voucher entry (AVL-P0-018). This is deliberately
/// not a financial record: it is never validated, never balanced, and never
/// posted automatically. It exists only so a crash or quit does not silently
/// discard everything the user typed into an open "new voucher" sheet, and
/// is deleted the moment the user explicitly posts or cancels that sheet.
public struct VoucherEntryDraft: Identifiable, Sendable, Hashable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var voucherTypeCode: VoucherType.Code
    /// Missing values in pre-V027 recovery rows decode as `.ledger`.
    public var entryMode: VoucherDraft.EntryMode
    public var date: Date
    public var partyAccountId: Account.ID?
    public var narration: String
    public var billReferenceType: VoucherDraft.BillReferenceType?
    public var billReferenceNumber: String?
    public var chequeNumber: String?
    public var chequeDueDate: Date?
    public var accountLedgerId: Account.ID?
    /// Explicit Sales/Purchase ledger for item-invoice entry mode. Scratch
    /// only: it is revalidated when the recovered draft is posted.
    public var salesPurchaseLedgerId: Account.ID?
    public var linesJSON: String
    /// Ordered raw item editor rows for item-invoice recovery.
    public var itemLinesJSON: String?
    /// Alt+2 duplicate lineage, set by `VoucherEditViewModel.duplicateDraft`
    /// and carried through crash recovery. `nil` for ordinary in-progress
    /// drafts.
    public var duplicatedFromVoucherId: Voucher.ID?
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                voucherTypeCode: VoucherType.Code,
                entryMode: VoucherDraft.EntryMode = .ledger,
                date: Date,
                partyAccountId: Account.ID? = nil,
                narration: String = "",
                billReferenceType: VoucherDraft.BillReferenceType? = nil,
                billReferenceNumber: String? = nil,
                chequeNumber: String? = nil,
                chequeDueDate: Date? = nil,
                accountLedgerId: Account.ID? = nil,
                salesPurchaseLedgerId: Account.ID? = nil,
                linesJSON: String,
                itemLinesJSON: String? = nil,
                duplicatedFromVoucherId: Voucher.ID? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.voucherTypeCode = voucherTypeCode
        self.entryMode = entryMode
        self.date = date
        self.partyAccountId = partyAccountId
        self.narration = narration
        self.billReferenceType = billReferenceType
        self.billReferenceNumber = billReferenceNumber
        self.chequeNumber = chequeNumber
        self.chequeDueDate = chequeDueDate
        self.accountLedgerId = accountLedgerId
        self.salesPurchaseLedgerId = salesPurchaseLedgerId
        self.linesJSON = linesJSON
        self.itemLinesJSON = itemLinesJSON
        self.duplicatedFromVoucherId = duplicatedFromVoucherId
        self.updatedAt = updatedAt
    }
}
