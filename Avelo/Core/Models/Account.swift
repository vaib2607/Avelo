import Foundation

public enum OpeningBalanceSide: String, CaseIterable, Sendable, Codable, Identifiable {
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

/// Tally party-ledger GST registration types (F11 > Statutory party profile).
public enum GSTRegistrationType: String, CaseIterable, Sendable, Codable, Identifiable {
    case regular
    case composition
    case unregistered
    case consumer
    case sez
    case export

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .regular:      return "Registered (Regular)"
        case .composition:  return "Registered (Composition)"
        case .unregistered: return "Unregistered"
        case .consumer:     return "Consumer"
        case .sez:          return "SEZ"
        case .export:       return "Export"
        }
    }
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var groupId: AccountGroup.ID
    public var code: String
    public var name: String
    public var openingBalancePaise: Int64
    public var openingBalanceSide: OpeningBalanceSide
    public var isActive: Bool
    public var isBankAccount: Bool
    public var gstin: String?
    // Tally ledger-master parity (all optional so old audit snapshots and
    // pre-v19 rows decode unchanged).
    public var mailingName: String?
    public var mailingAddress: String?
    public var stateCode: String?          // 2-digit GST state code
    public var country: String?
    public var gstRegistrationType: GSTRegistrationType?
    public var maintainBillwise: Bool?
    public var creditPeriodDays: Int?
    public var lastUsedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                groupId: AccountGroup.ID,
                code: String,
                name: String,
                openingBalancePaise: Int64 = 0,
                openingBalanceSide: OpeningBalanceSide = .debit,
                isActive: Bool = true,
                isBankAccount: Bool = false,
                gstin: String? = nil,
                mailingName: String? = nil,
                mailingAddress: String? = nil,
                stateCode: String? = nil,
                country: String? = nil,
                gstRegistrationType: GSTRegistrationType? = nil,
                maintainBillwise: Bool? = nil,
                creditPeriodDays: Int? = nil,
                lastUsedAt: Date? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.groupId = groupId
        self.code = code
        self.name = name
        self.openingBalancePaise = openingBalancePaise
        self.openingBalanceSide = openingBalanceSide
        self.isActive = isActive
        self.isBankAccount = isBankAccount
        self.gstin = gstin
        self.mailingName = mailingName
        self.mailingAddress = mailingAddress
        self.stateCode = stateCode
        self.country = country
        self.gstRegistrationType = gstRegistrationType
        self.maintainBillwise = maintainBillwise
        self.creditPeriodDays = creditPeriodDays
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func signedOpeningBalancePaise() throws -> Int64 {
        switch openingBalanceSide {
        case .debit:
            return openingBalancePaise
        case .credit:
            return try CheckedMath.multiply(
                openingBalancePaise,
                -1,
                context: "calculating signed opening balance"
            )
        }
    }
}
