import Foundation

public enum AuditAction: String, CaseIterable, Sendable, Codable, Identifiable {
    case companyCreated
    case companyUpdated
    case financialYearCreated
    case financialYearLocked
    case financialYearClosed
    case accountCreated
    case accountUpdated
    case accountDisabled
    case voucherPosted
    case voucherEdited
    case voucherReversed
    case openingBalancePosted
    case stockItemCreated
    case stockItemUpdated
    case stockItemDisabled
    case stockMovementPosted
    case stockMovementReversed
    case payrollEmployeeCreated
    case payrollEmployeeUpdated
    case payrollEmployeeTerminated
    case salaryPosted
    case backupExported
    case backupImported
    case companySwitched
    case financialYearSwitched
    case inventoryModeChanged
    case fyUnlocked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .companyCreated:           return "Company created"
        case .companyUpdated:           return "Company updated"
        case .financialYearCreated:     return "Financial year created"
        case .financialYearLocked:      return "Financial year locked"
        case .financialYearClosed:      return "Financial year closed"
        case .fyUnlocked:               return "Financial year unlocked"
        case .accountCreated:           return "Account created"
        case .accountUpdated:           return "Account updated"
        case .accountDisabled:          return "Account disabled"
        case .voucherPosted:            return "Voucher posted"
        case .voucherEdited:            return "Voucher edited"
        case .voucherReversed:          return "Voucher reversed"
        case .openingBalancePosted:     return "Opening balances posted"
        case .stockItemCreated:         return "Stock item created"
        case .stockItemUpdated:         return "Stock item updated"
        case .stockItemDisabled:        return "Stock item disabled"
        case .stockMovementPosted:      return "Stock movement posted"
        case .stockMovementReversed:    return "Stock movement reversed"
        case .payrollEmployeeCreated:   return "Employee created"
        case .payrollEmployeeUpdated:   return "Employee updated"
        case .payrollEmployeeTerminated:return "Employee terminated"
        case .salaryPosted:             return "Salary posted"
        case .backupExported:           return "Backup exported"
        case .backupImported:           return "Backup imported"
        case .companySwitched:          return "Company switched"
        case .financialYearSwitched:    return "Financial year switched"
        case .inventoryModeChanged:     return "Inventory mode changed"
        }
    }
}

public struct AuditEvent: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var timestamp: Date
    public var actor: String
    public var action: AuditAction
    public var entityType: String
    public var entityId: String
    public var snapshotBeforeJson: String?
    public var snapshotAfterJson: String?
    public var reason: String?

    public init(id: ID = UUID(),
                companyId: Company.ID,
                timestamp: Date = Date(),
                actor: String = "user",
                action: AuditAction,
                entityType: String,
                entityId: String,
                snapshotBeforeJson: String? = nil,
                snapshotAfterJson: String? = nil,
                reason: String? = nil) {
        self.id = id
        self.companyId = companyId
        self.timestamp = timestamp
        self.actor = actor
        self.action = action
        self.entityType = entityType
        self.entityId = entityId
        self.snapshotBeforeJson = snapshotBeforeJson
        self.snapshotAfterJson = snapshotAfterJson
        self.reason = reason
    }
}
