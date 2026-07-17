import Foundation

public struct VoucherDraft: Sendable, Hashable {
    public enum BillReferenceType: String, CaseIterable, Sendable, Hashable, Codable, Identifiable {
        case newRef = "New Ref"
        case agstRef = "Agst Ref"
        case advance = "Advance"
        case onAccount = "On Account"

        public var id: String { rawValue }
    }

    public enum Mode: Sendable, Hashable {
        case create
        case edit(originalVoucherId: Voucher.ID)

        public var originalVoucherId: Voucher.ID? {
            if case .edit(let id) = self { return id }
            return nil
        }
    }

    public struct Line: Identifiable, Hashable, Sendable {
        public let id: UUID
        public var accountId: Account.ID?
        public var amountPaise: Int64
        public var side: EntrySide
        public var taxCode: String?
        public var costCenter: String?
        public var lineOrder: Int

        public init(id: UUID = UUID(),
                    accountId: Account.ID? = nil,
                    amountPaise: Int64 = 0,
                    side: EntrySide = .debit,
                    taxCode: String? = nil,
                    costCenter: String? = nil,
                    lineOrder: Int = 0) {
            self.id = id
            self.accountId = accountId
            self.amountPaise = amountPaise
            self.side = side
            self.taxCode = taxCode
            self.costCenter = costCenter
            self.lineOrder = lineOrder
        }

        public var amount: String { Currency.formatAmountInput(paise: amountPaise) }
    }

    public var mode: Mode
    public var voucherTypeCode: VoucherType.Code
    public var date: Date
    public var partyAccountId: Account.ID?
    public var billReferenceType: BillReferenceType?
    public var billReferenceNumber: String?
    public var narration: String
    public var lines: [Line]

    public init(mode: Mode,
                voucherTypeCode: VoucherType.Code,
                date: Date,
                partyAccountId: Account.ID? = nil,
                billReferenceType: BillReferenceType? = nil,
                billReferenceNumber: String? = nil,
                narration: String = "",
                lines: [Line] = []) {
        self.mode = mode
        self.voucherTypeCode = voucherTypeCode
        self.date = date
        self.partyAccountId = partyAccountId
        self.billReferenceType = billReferenceType
        self.billReferenceNumber = billReferenceNumber
        self.narration = narration
        self.lines = lines
    }

    public var totalDebitPaise: Int64 {
        lines.filter { $0.side == EntrySide.debit }.reduce(0) { $0 + $1.amountPaise }
    }

    public var totalCreditPaise: Int64 {
        lines.filter { $0.side == EntrySide.credit }.reduce(0) { $0 + $1.amountPaise }
    }

    public var differencePaise: Int64 { totalDebitPaise - totalCreditPaise }

    public var isBalanced: Bool { differencePaise == 0 }

    public var filledLines: [Line] {
        lines.filter { $0.accountId != nil && $0.amountPaise > 0 }
    }
}
