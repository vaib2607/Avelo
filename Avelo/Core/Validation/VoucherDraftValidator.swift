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

        do {
            let totals = try draft.checkedTotals()
            if totals.difference != 0 {
                let dr = Currency.formatPaise(totals.debit, style: .indianGrouping)
                let cr = Currency.formatPaise(totals.credit, style: .indianGrouping)
                let diff = Currency.formatAbsolutePaise(totals.difference, style: .indianGrouping)
                let larger = totals.difference > 0 ? "debit" : "credit"
                errors.append(ValidationError(
                    code: .voucherDebitCreditMismatch,
                    field: "lines",
                    message: "Debit total (\(dr)) does not match Credit total (\(cr)). Difference: \(diff) on \(larger) side.",
                    suggestedFix: "Adjust amounts so debit equals credit."
                ))
            }
        } catch {
            errors.append(ValidationError(
                code: .arithmeticOverflow,
                field: "lines",
                message: "Voucher totals overflow Int64 while validating debit and credit lines."
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

        do {
            if let fyId = try fyIdForDate(draft.date, companyId: companyId) {
                if fyId != financialYearId {
                    errors.append(ValidationError(
                        code: .voucherDateOutsideFY,
                        field: "date",
                        message: "Date \(DateFormatters.formatDisplayDate(draft.date)) is outside the active financial year."
                    ))
                }
            } else {
                errors.append(ValidationError(
                    code: .voucherDateOutsideFY,
                    field: "date",
                    message: "Date \(DateFormatters.formatDisplayDate(draft.date)) is not within any open financial year."
                ))
            }
        } catch {
            errors.append(ValidationError(
                code: .internal,
                field: "date",
                message: "Unable to validate the voucher date against financial years."
            ))
        }

        do {
            if try fiscalLockChecker.isLocked(financialYearId: financialYearId) {
                errors.append(ValidationError(
                    code: .voucherFYLocked,
                    field: "date",
                    message: existingVoucherId == nil
                        ? "Financial year is locked; new vouchers are not allowed."
                        : "Financial year is locked; voucher edits are not allowed."
                ))
            }
        } catch {
            errors.append(ValidationError(
                code: .internal,
                field: "date",
                message: "Unable to validate fiscal-year lock state."
            ))
        }

        if existingVoucherId == nil {
            for line in filled {
                if let acc = line.accountId {
                    do {
                        if try isAccountActive(acc, companyId: companyId) == false {
                            errors.append(ValidationError(
                                code: .voucherAccountInactive,
                                field: "lines",
                                message: "Account is inactive."
                            ))
                        }
                    } catch {
                        errors.append(ValidationError(
                            code: .internal,
                            field: "lines",
                            message: "Unable to validate account activity."
                        ))
                    }
                }
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private func fyIdForDate(_ date: Date, companyId: Company.ID) throws -> FinancialYear.ID? {
        try fiscalLockChecker.financialYear(containing: date, companyId: companyId)
    }

    private func isAccountActive(_ id: Account.ID, companyId: Company.ID) throws -> Bool {
        let v: Int64? = try db.queryOne(
            "SELECT is_active FROM avelo_accounts WHERE id = ? AND company_id = ?",
            bind: [.text(id.uuidString), .text(companyId.uuidString)]
        ) { r in r.int("is_active") }
        return (v ?? 0) != 0
    }
}
