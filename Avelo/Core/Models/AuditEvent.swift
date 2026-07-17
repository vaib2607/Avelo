import Foundation

public enum AuditAction: String, CaseIterable, Sendable, Codable, Identifiable {
    case companyCreated
    case companyUpdated
    case financialYearCreated
    case financialYearLocked
    case financialYearClosed
    case financialYearUnlocked
    case financialYearReopened
    case accountCreated
    case accountUpdated
    case accountDisabled
    case accountGroupCreated
    case accountGroupUpdated
    case accountGroupDeleted
    case voucherPosted
    case voucherEdited
    case voucherReversed
    case voucherCancelled
    case chequeBounced
    case chequeRepresented
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
<<<<<<< HEAD:Avelo/Core/Models/AuditEvent.swift
    case bankStatementImported
    case bankStatementLineCleared
    case inventoryOrderCreated
    case inventoryOrderFulfilled
    case inventoryOrderStatusChanged
    case inventoryReorderLevelSet
    case billOfMaterialsCreated
    case billOfMaterialsUpdated
    case voucherTemplateSaved
    case gstReportExported
    case invoicePDFExported
=======
    case inventoryModeChanged
    case fyUnlocked
    case inventoryEnabled
    case itemCreated
    case itemUpdated
    case itemArchived
    case itemAccountLinked
    case stockMoved
    case employeeCreated
    case employeeUpdated
    case employeeDeactivated
    case payrollEntryPosted
    case bankStatementImported
    case bankStatementLineCleared
    case bankReconciled
>>>>>>> origin/main:Mally/Core/Models/AuditEvent.swift

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .companyCreated:           return "Company created"
        case .companyUpdated:           return "Company updated"
        case .financialYearCreated:     return "Financial year created"
        case .financialYearLocked:      return "Financial year locked"
        case .financialYearClosed:      return "Financial year closed"
        case .financialYearUnlocked:    return "Financial year unlocked"
        case .financialYearReopened:    return "Financial year reopened"
        case .accountCreated:           return "Account created"
        case .accountUpdated:           return "Account updated"
        case .accountDisabled:          return "Account disabled"
        case .accountGroupCreated:      return "Account group created"
        case .accountGroupUpdated:      return "Account group updated"
        case .accountGroupDeleted:      return "Account group deleted"
        case .voucherPosted:            return "Voucher posted"
        case .voucherEdited:            return "Voucher edited"
        case .voucherReversed:          return "Voucher reversed"
        case .voucherCancelled:         return "Voucher cancelled"
        case .chequeBounced:            return "Cheque bounced"
        case .chequeRepresented:        return "Cheque re-presented"
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
<<<<<<< HEAD:Avelo/Core/Models/AuditEvent.swift
        case .bankStatementImported:    return "Bank statement imported"
        case .bankStatementLineCleared: return "Bank statement line cleared"
        case .inventoryOrderCreated:    return "Inventory order created"
        case .inventoryOrderFulfilled:  return "Inventory order fulfilled"
        case .inventoryOrderStatusChanged: return "Inventory order status changed"
        case .inventoryReorderLevelSet: return "Reorder level set"
        case .billOfMaterialsCreated:   return "Bill of materials created"
        case .billOfMaterialsUpdated:   return "Bill of materials updated"
        case .voucherTemplateSaved:     return "Voucher template saved"
        case .gstReportExported:        return "GST report exported"
        case .invoicePDFExported:       return "Invoice PDF exported"
=======
        case .inventoryModeChanged:     return "Inventory mode changed"
        case .inventoryEnabled:         return "Inventory enabled"
        case .itemCreated:              return "Item created"
        case .itemUpdated:              return "Item updated"
        case .itemArchived:             return "Item archived"
        case .itemAccountLinked:        return "Item account linked"
        case .stockMoved:               return "Stock moved"
        case .employeeCreated:          return "Employee created"
        case .employeeUpdated:          return "Employee updated"
        case .employeeDeactivated:      return "Employee deactivated"
        case .payrollEntryPosted:       return "Payroll entry posted"
        case .bankStatementImported:    return "Bank statement imported"
        case .bankStatementLineCleared: return "Bank statement line cleared"
        case .bankReconciled:           return "Bank reconciled"
>>>>>>> origin/main:Mally/Core/Models/AuditEvent.swift
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
