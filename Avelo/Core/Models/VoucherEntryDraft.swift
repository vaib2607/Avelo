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
    public var date: Date
    public var partyAccountId: Account.ID?
    public var narration: String
    public var billReferenceType: VoucherDraft.BillReferenceType?
    public var billReferenceNumber: String?
    public var chequeNumber: String?
    public var chequeDueDate: Date?
    public var accountLedgerId: Account.ID?
    public var linesJSON: String
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                voucherTypeCode: VoucherType.Code,
                date: Date,
                partyAccountId: Account.ID? = nil,
                narration: String = "",
                billReferenceType: VoucherDraft.BillReferenceType? = nil,
                billReferenceNumber: String? = nil,
                chequeNumber: String? = nil,
                chequeDueDate: Date? = nil,
                accountLedgerId: Account.ID? = nil,
                linesJSON: String,
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.voucherTypeCode = voucherTypeCode
        self.date = date
        self.partyAccountId = partyAccountId
        self.narration = narration
        self.billReferenceType = billReferenceType
        self.billReferenceNumber = billReferenceNumber
        self.chequeNumber = chequeNumber
        self.chequeDueDate = chequeDueDate
        self.accountLedgerId = accountLedgerId
        self.linesJSON = linesJSON
        self.updatedAt = updatedAt
    }
}
