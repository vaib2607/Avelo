import Foundation

public struct VoucherDraft: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case create
        case edit(originalVoucherId: Voucher.ID)
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

        public var isEmpty: Bool {
            accountId == nil && amountPaise == 0
        }
    }

    public var mode: Mode
    public var voucherTypeCode: VoucherType.Code
    public var date: Date
    public var partyAccountId: Account.ID?
    public var narration: String
    public var reference: String
    public var lines: [Line]

    public init(mode: Mode = .create,
                voucherTypeCode: VoucherType.Code = .journal,
                date: Date = Date(),
                partyAccountId: Account.ID? = nil,
                narration: String = "",
                reference: String = "",
                lines: [Line]? = nil) {
        self.mode = mode
        self.voucherTypeCode = voucherTypeCode
        self.date = date
        self.partyAccountId = partyAccountId
        self.narration = narration
        self.reference = reference
        if let lines = lines {
            self.lines = lines
        } else {
            self.lines = [
                Line(lineOrder: 0),
                Line(side: .credit, lineOrder: 1)
            ]
        }
    }

    public static var empty: VoucherDraft { VoucherDraft() }

    public var totalDebitPaise: Int64 {
        lines.filter { $0.side == .debit }.reduce(0) { $0 + $1.amountPaise }
    }

    public var totalCreditPaise: Int64 {
        lines.filter { $0.side == .credit }.reduce(0) { $0 + $1.amountPaise }
    }

    public var differencePaise: Int64 {
        totalDebitPaise - totalCreditPaise
    }

    public var isBalanced: Bool {
        differencePaise == 0
    }

    public var nonEmptyLines: [Line] {
        lines.filter { !$0.isEmpty }
    }

    public var filledLines: [Line] {
        lines.filter { $0.accountId != nil && $0.amountPaise > 0 }
    }
}
