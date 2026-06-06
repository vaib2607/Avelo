import Foundation

public struct VoucherDraftValidator: Sendable {

    public let db: SQLiteDatabase
    public let fiscalLockChecker: FiscalLockChecker

    public init(db: SQLiteDatabase, fiscalLockChecker: FiscalLockChecker) {
        self.db = db
        self.fiscalLockChecker = fiscalLockChecker
    }

    public func validate(_ draft: VoucherDraft,
                         companyId: Company.ID,
                         financialYearId: FinancialYear.ID,
                         existingVoucherId: Voucher.ID? = nil) -> ValidationResult {
        var errors: [ValidationError] = []

        let filled = draft.filledLines
        if filled.count < 2 {
            errors.append(ValidationError(
                code: .voucherTooFewLines,
                field: "lines",
                message: "Each voucher needs at least two lines.",
                suggestedFix: "Add at least one debit and one credit line."
            ))
        }

        for line in filled where line.amountPaise <= 0 {
            errors.append(ValidationError(
                code: .voucherZeroAmountLine,
                field: "lines",
                message: "Amount must be greater than zero."
            ))
        }

        let accountIds = filled.compactMap { $0.accountId }
        let uniqueAccountIds = Set(accountIds)
        if uniqueAccountIds.count != accountIds.count {
            errors.append(ValidationError(
                code: .voucherDuplicateAccount,
                field: "lines",
                message: "Duplicate account in lines."
            ))
        }

        if !draft.isBalanced {
            let dr = Currency.formatPaise(draft.totalDebitPaise, style: .indianGrouping)
            let cr = Currency.formatPaise(draft.totalCreditPaise, style: .indianGrouping)
            let diff = Currency.formatPaise(abs(draft.differencePaise), style: .indianGrouping)
            let larger = draft.differencePaise > 0 ? "debit" : "credit"
            errors.append(ValidationError(
                code: .voucherDebitCreditMismatch,
                field: "lines",
                message: "Debit total (\(dr)) does not match Credit total (\(cr)). Difference: \(diff) on \(larger) side.",
                suggestedFix: "Adjust amounts so debit equals credit."
            ))
        }

        switch draft.voucherTypeCode {
        case .creditNote:
            if draft.partyAccountId == nil {
                errors.append(ValidationError(
                    code: .voucherMissingParty,
                    field: "party",
                    message: "Credit Note requires a debtor party account."
                ))
            }
            if draft.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    code: .voucherMissingNarration,
                    field: "narration",
                    message: "Narration is required for Credit Note."
                ))
            }
        case .debitNote:
            if draft.partyAccountId == nil {
                errors.append(ValidationError(
                    code: .voucherMissingParty,
                    field: "party",
                    message: "Debit Note requires a creditor party account."
                ))
            }
            if draft.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    code: .voucherMissingNarration,
                    field: "narration",
                    message: "Narration is required for Debit Note."
                ))
            }
        case .payroll:
            if draft.partyAccountId == nil {
                errors.append(ValidationError(
                    code: .voucherMissingParty,
                    field: "party",
                    message: "Payroll voucher requires a party (employee payable or expense) account."
                ))
            }
            if draft.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    code: .voucherMissingNarration,
                    field: "narration",
                    message: "Narration is required for Payroll."
                ))
            }
        case .opening:
            if draft.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(ValidationError(
                    code: .voucherMissingNarration,
                    field: "narration",
                    message: "Narration is required for Opening Balance."
                ))
            }
        default:
            break
        }

        if let fyId = try? fyIdForDate(draft.date, companyId: companyId) {
            if fyId != financialYearId {
                errors.append(ValidationError(
                    code: .voucherDateOutsideFY,
                    field: "date",
                    message: "Date \(DateFormatters.displayDate(draft.date)) is outside the active financial year."
                ))
            }
        } else {
            errors.append(ValidationError(
                code: .voucherDateOutsideFY,
                field: "date",
                message: "Date \(DateFormatters.displayDate(draft.date)) is not within any open financial year."
            ))
        }

        if (try? fiscalLockChecker.isLocked(financialYearId: financialYearId)) == true {
            if existingVoucherId == nil {
                errors.append(ValidationError(
                    code: .voucherFYLocked,
                    field: "date",
                    message: "Financial year is locked; new vouchers are not allowed."
                ))
            }
        }

        for line in filled {
            if let acc = line.accountId,
               let isActive = try? isAccountActive(acc, companyId: companyId),
               !isActive {
                errors.append(ValidationError(
                    code: .voucherAccountInactive,
                    field: "lines",
                    message: "Account is inactive."
                ))
                break
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private func fyIdForDate(_ date: Date, companyId: Company.ID) throws -> FinancialYear.ID? {
        try fiscalLockChecker.financialYear(containing: date, companyId: companyId)
    }

    private func isAccountActive(_ id: Account.ID, companyId: Company.ID) throws -> Bool {
        let v: Int64? = try db.queryOne(
            "SELECT is_active FROM mally_accounts WHERE id = ? AND company_id = ?",
            bind: [.text(id.uuidString), .text(companyId.uuidString)]
        ) { r in r.int("is_active") }
        return (v ?? 0) != 0
    }
}
