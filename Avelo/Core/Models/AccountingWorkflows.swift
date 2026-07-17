import Foundation

public enum BillAllocationKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case newRef = "New Ref"
    case agstRef = "Agst Ref"
    case advance = "Advance"
    case onAccount = "On Account"
    public var id: String { rawValue }
}

public struct BillAllocation: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public let voucherId: Voucher.ID
    public let partyAccountId: Account.ID
    public var kind: BillAllocationKind
    public var referenceNumber: String?
    public var allocatedPaise: Int64
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, voucherId: Voucher.ID, partyAccountId: Account.ID, kind: BillAllocationKind, referenceNumber: String? = nil, allocatedPaise: Int64, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.voucherId = voucherId; self.partyAccountId = partyAccountId; self.kind = kind; self.referenceNumber = referenceNumber; self.allocatedPaise = allocatedPaise; self.createdAt = createdAt
    }
}

public enum ChequeStatus: String, CaseIterable, Sendable, Codable, Identifiable {
    case issued, deposited, cleared, bounced, cancelled
    public var id: String { rawValue }
}

public struct Cheque: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public var voucherId: Voucher.ID
    public var chequeNumber: String
    public var bankAccountId: Account.ID?
    public var issueDate: Date
    public var dueDate: Date?
    public var status: ChequeStatus
<<<<<<< HEAD
    public var bouncedReversalVoucherId: Voucher.ID?
    public var representedFromChequeId: ID?
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, voucherId: Voucher.ID, chequeNumber: String, bankAccountId: Account.ID? = nil, issueDate: Date, dueDate: Date? = nil, status: ChequeStatus = .issued, bouncedReversalVoucherId: Voucher.ID? = nil, representedFromChequeId: ID? = nil, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.voucherId = voucherId; self.chequeNumber = chequeNumber; self.bankAccountId = bankAccountId; self.issueDate = issueDate; self.dueDate = dueDate; self.status = status; self.bouncedReversalVoucherId = bouncedReversalVoucherId; self.representedFromChequeId = representedFromChequeId; self.createdAt = createdAt
=======
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, voucherId: Voucher.ID, chequeNumber: String, bankAccountId: Account.ID? = nil, issueDate: Date, dueDate: Date? = nil, status: ChequeStatus = .issued, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.voucherId = voucherId; self.chequeNumber = chequeNumber; self.bankAccountId = bankAccountId; self.issueDate = issueDate; self.dueDate = dueDate; self.status = status; self.createdAt = createdAt
>>>>>>> origin/main
    }
}

public struct TDSRecord: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public let voucherId: Voucher.ID
    public var sectionCode: String
    public var basePaise: Int64
    public var taxPaise: Int64
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, voucherId: Voucher.ID, sectionCode: String, basePaise: Int64, taxPaise: Int64, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.voucherId = voucherId; self.sectionCode = sectionCode; self.basePaise = basePaise; self.taxPaise = taxPaise; self.createdAt = createdAt
    }
}

public struct TCSRecord: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID
    public let id: ID
    public let companyId: Company.ID
    public let voucherId: Voucher.ID
    public var sectionCode: String
    public var basePaise: Int64
    public var taxPaise: Int64
    public let createdAt: Date
    public init(id: ID = UUID(), companyId: Company.ID, voucherId: Voucher.ID, sectionCode: String, basePaise: Int64, taxPaise: Int64, createdAt: Date = Date()) {
        self.id = id; self.companyId = companyId; self.voucherId = voucherId; self.sectionCode = sectionCode; self.basePaise = basePaise; self.taxPaise = taxPaise; self.createdAt = createdAt
    }
}
