import Foundation

public struct Voucher: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var financialYearId: FinancialYear.ID
    public var voucherTypeCode: VoucherType.Code
    public var number: String
    public var date: Date
    public var partyAccountId: Account.ID?
    public var narration: String
    public var isReversal: Bool
    public var reversalOfId: ID?
    public var isPosted: Bool
    public var totalPaise: Int64
    public let createdAt: Date
    public var updatedAt: Date
    public var reference: String

    public init(id: ID = UUID(),
                companyId: Company.ID,
                financialYearId: FinancialYear.ID,
                voucherTypeCode: VoucherType.Code,
                number: String,
                date: Date,
                partyAccountId: Account.ID? = nil,
                narration: String = "",
                isReversal: Bool = false,
                reversalOfId: ID? = nil,
                isPosted: Bool = true,
                totalPaise: Int64 = 0,
                reference: String = "",
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.financialYearId = financialYearId
        self.voucherTypeCode = voucherTypeCode
        self.number = number
        self.date = date
        self.partyAccountId = partyAccountId
        self.narration = narration
        self.isReversal = isReversal
        self.reversalOfId = reversalOfId
        self.isPosted = isPosted
        self.totalPaise = totalPaise
        self.reference = reference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LedgerLine: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var voucherId: Voucher.ID
    public var accountId: Account.ID
    public var amountPaise: Int64
    public var side: EntrySide
    public var taxCode: String?
    public var costCenter: String?
    public var lineOrder: Int

    public init(id: ID = UUID(),
                companyId: Company.ID,
                voucherId: Voucher.ID,
                accountId: Account.ID,
                amountPaise: Int64,
                side: EntrySide,
                taxCode: String? = nil,
                costCenter: String? = nil,
                lineOrder: Int) {
        self.id = id
        self.companyId = companyId
        self.voucherId = voucherId
        self.accountId = accountId
        self.amountPaise = amountPaise
        self.side = side
        self.taxCode = taxCode
        self.costCenter = costCenter
        self.lineOrder = lineOrder
    }

    public func signedAmountPaise() -> Int64 {
        switch side {
        case .debit:  return amountPaise
        case .credit: return -amountPaise
        }
    }
}

public enum EntrySide: String, CaseIterable, Sendable, Codable, Identifiable, Hashable {
    case debit
    case credit
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .debit:  return "Dr"
        case .credit: return "Cr"
        }
    }
}

public typealias LedgerSide = EntrySide
