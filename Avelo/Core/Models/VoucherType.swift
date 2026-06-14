import Foundation

public struct VoucherType: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public enum Code: String, CaseIterable, Sendable, Codable, Identifiable {
        case journal
        case sales
        case purchase
        case payment
        case receipt
        case contra
        case creditNote
        case debitNote
        case opening
        case payroll

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .journal:     return "Journal"
            case .sales:       return "Sales"
            case .purchase:    return "Purchase"
            case .payment:     return "Payment"
            case .receipt:     return "Receipt"
            case .contra:      return "Contra"
            case .creditNote:  return "Credit Note"
            case .debitNote:   return "Debit Note"
            case .opening:     return "Opening Balance"
            case .payroll:     return "Payroll"
            }
        }

        public var abbreviation: String {
            switch self {
            case .journal:     return "JV"
            case .sales:       return "SALES"
            case .purchase:    return "PURCH"
            case .payment:     return "PAY"
            case .receipt:     return "RCT"
            case .contra:      return "CON"
            case .creditNote:  return "CN"
            case .debitNote:   return "DN"
            case .opening:     return "OPN"
            case .payroll:     return "PAYROLL"
            }
        }

        public var affectsInventory: Bool {
            switch self {
            case .sales, .purchase, .creditNote, .debitNote: return true
            default: return false
            }
        }

        public var defaultPrefix: String {
            switch self {
            case .sales:       return "S"
            case .purchase:    return "P"
            case .payment:     return "PAY"
            case .receipt:     return "RCT"
            case .contra:      return "CON"
            case .creditNote:  return "CN"
            case .debitNote:   return "DN"
            case .opening:     return "OPN"
            case .payroll:     return "PAYROLL"
            case .journal:     return "JV"
            }
        }

        public var defaultPadding: Int {
            switch self {
            case .payroll, .payment, .receipt, .contra: return 5
            case .opening: return 4
            default: return 5
            }
        }
    }

    public let id: ID
    public let companyId: Company.ID
    public let code: Code
    public var name: String
    public var abbreviation: String
    public var isSystem: Bool
    public var affectsInventory: Bool
    public var sortOrder: Int
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: Code,
                name: String? = nil,
                abbreviation: String? = nil,
                isSystem: Bool = true,
                affectsInventory: Bool? = nil,
                sortOrder: Int = 0,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name ?? code.displayName
        self.abbreviation = abbreviation ?? code.abbreviation
        self.isSystem = isSystem
        self.affectsInventory = affectsInventory ?? code.affectsInventory
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
