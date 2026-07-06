import Foundation

public enum VoucherStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case open
    case cancelled
}

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
    public var status: VoucherStatus
    public var isReversal: Bool
    public var reversalOfId: ID?
    public var cancelledAt: Date?
    public var cancelledBy: String?
    public var cancellationReason: String?
    public var cancellationVoucherId: ID?
    public var isPosted: Bool
    public var totalPaise: Int64
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                financialYearId: FinancialYear.ID,
                voucherTypeCode: VoucherType.Code,
                number: String,
                date: Date,
                partyAccountId: Account.ID? = nil,
                narration: String = "",
                status: VoucherStatus = .open,
                isReversal: Bool = false,
                reversalOfId: ID? = nil,
                cancelledAt: Date? = nil,
                cancelledBy: String? = nil,
                cancellationReason: String? = nil,
                cancellationVoucherId: ID? = nil,
                isPosted: Bool = true,
                totalPaise: Int64 = 0,
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
        self.status = status
        self.isReversal = isReversal
        self.reversalOfId = reversalOfId
        self.cancelledAt = cancelledAt
        self.cancelledBy = cancelledBy
        self.cancellationReason = cancellationReason
        self.cancellationVoucherId = cancellationVoucherId
        self.isPosted = isPosted
        self.totalPaise = totalPaise
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

    public func signedAmountPaise() throws -> Int64 {
        switch side {
        case .debit:
            return amountPaise
        case .credit:
            return try CheckedMath.multiply(
                amountPaise,
                -1,
                context: "calculating signed ledger line amount"
            )
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
