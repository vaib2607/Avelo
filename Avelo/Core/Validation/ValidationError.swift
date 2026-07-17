import Foundation

public enum ValidationErrorCode: String, CaseIterable, Sendable, Codable, Identifiable {
    case voucherDebitCreditMismatch
    case voucherTooFewLines
    case voucherZeroAmountLine
    case voucherDuplicateAccount
    case voucherAccountIsGroup
    case voucherAccountInactive
    case voucherDateOutsideFY
    case voucherFYLocked
    case voucherMissingParty
    case voucherMissingNarration
    case accountNameBlank
    case accountCodeDuplicate
    case accountGroupRequired
    case accountOpeningBalanceRequired
    case financialYearOverlap
    case financialYearGapNotAllowed
    case financialYearZeroLength
    case companyNameBlank
    case companyGstinInvalid
    case companyPanInvalid
    case payrollNetMismatch
    case payrollEmployeeTerminated
    case stockMovementQuantityZero
    case stockMovementCostMismatch
    case quantityExceedsStock
<<<<<<< HEAD:Avelo/Core/Validation/ValidationError.swift
    case arithmeticOverflow
=======
>>>>>>> origin/main:Mally/Core/Validation/ValidationError.swift
    case `internal`

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .voucherDebitCreditMismatch: return "Voucher out of balance"
        case .voucherTooFewLines:          return "Voucher needs more lines"
        case .voucherZeroAmountLine:       return "Voucher has zero amount"
        case .voucherDuplicateAccount:     return "Duplicate account in voucher"
        case .voucherAccountIsGroup:       return "Group used as ledger"
        case .voucherAccountInactive:      return "Account is inactive"
        case .voucherDateOutsideFY:        return "Date outside financial year"
        case .voucherFYLocked:             return "Financial year is locked"
        case .voucherMissingParty:         return "Party account required"
        case .voucherMissingNarration:     return "Narration required"
        case .accountNameBlank:            return "Account name blank"
        case .accountCodeDuplicate:        return "Account code duplicate"
        case .accountGroupRequired:        return "Group required"
        case .accountOpeningBalanceRequired:return "Opening balance required"
        case .financialYearOverlap:        return "Financial year overlap"
        case .financialYearGapNotAllowed:  return "Financial year gap"
        case .financialYearZeroLength:     return "Financial year zero length"
        case .companyNameBlank:            return "Company name blank"
        case .companyGstinInvalid:         return "GSTIN invalid"
        case .companyPanInvalid:           return "PAN invalid"
        case .payrollNetMismatch:          return "Salary net mismatch"
        case .payrollEmployeeTerminated:   return "Employee terminated"
        case .stockMovementQuantityZero:   return "Stock movement qty zero"
        case .stockMovementCostMismatch:   return "Stock movement cost mismatch"
        case .quantityExceedsStock:        return "Quantity exceeds stock"
<<<<<<< HEAD:Avelo/Core/Validation/ValidationError.swift
        case .arithmeticOverflow:          return "Arithmetic overflow"
=======
>>>>>>> origin/main:Mally/Core/Validation/ValidationError.swift
        case .`internal`:                  return "Internal error"
        }
    }
}

public struct ValidationError: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let code: ValidationErrorCode
    public let field: String?
    public let message: String
    public let suggestedFix: String?

    public init(id: UUID = UUID(),
                code: ValidationErrorCode,
                field: String? = nil,
                message: String,
                suggestedFix: String? = nil) {
        self.id = id
        self.code = code
        self.field = field
        self.message = message
        self.suggestedFix = suggestedFix
    }
}
