import Foundation

public struct VoucherDraftValidator: Sendable {

    /// A transaction-scoped snapshot used by bulk posting. It eliminates
    /// repeated reads without changing the validation data or decisions: the
    /// caller creates it inside the same write transaction that posts the
    /// vouchers, so financial-year and account state cannot change beneath
    /// the batch.
    struct BatchContext: Sendable {
        private let financialYears: [FinancialYear]
        private let accountActivityById: [Account.ID: Bool]
        let cashOrBankAccountIDs: Set<Account.ID>

        init(financialYears: [FinancialYear],
             accountActivityById: [Account.ID: Bool],
             cashOrBankAccountIDs: Set<Account.ID>) {
            self.financialYears = financialYears
            self.accountActivityById = accountActivityById
            self.cashOrBankAccountIDs = cashOrBankAccountIDs
        }

        func financialYearId(containing date: Date) throws -> FinancialYear.ID? {
            let matches = financialYears.filter { $0.contains(date: date) }
            if matches.count > 1 {
                let labels = matches.map(\.label).joined(separator: ", ")
                throw AppError.businessRule("Overlapping financial years make date lookup ambiguous: \(labels)")
            }
            return matches.first?.id
        }

        func isLocked(financialYearId: FinancialYear.ID) -> Bool {
            financialYears.first(where: { $0.id == financialYearId })?.isLocked ?? false
        }

        func isAccountActive(_ id: Account.ID) -> Bool {
            accountActivityById[id] ?? false
        }
    }

    public let db: SQLiteDatabase
    public let fiscalLockChecker: FiscalLockChecker

    public init(db: SQLiteDatabase, fiscalLockChecker: FiscalLockChecker) {
        self.db = db
        self.fiscalLockChecker = fiscalLockChecker
    }

    func makeBatchContext(companyId: Company.ID) throws -> BatchContext {
        let financialYears = try FinancialYearRepository(db: db).listForCompany(companyId)
        let accounts = try AccountRepository(db: db).listForCompany(companyId)
        let groups = try AccountGroupRepository(db: db).listForCompany(companyId)
        let groupCodesByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.code) })
        let accountActivityById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.isActive) })
        let cashOrBankAccountIDs = Set(accounts.lazy.filter {
            isCashOrBank($0, groupCodesByID: groupCodesByID)
        }.map(\.id))
        return BatchContext(
            financialYears: financialYears,
            accountActivityById: accountActivityById,
            cashOrBankAccountIDs: cashOrBankAccountIDs
        )
    }

    public func validate(_ draft: VoucherDraft,
                         companyId: Company.ID,
                         financialYearId: FinancialYear.ID,
                         existingVoucherId: Voucher.ID? = nil,
                         isSystemReversal: Bool = false) -> ValidationResult {
        validate(
            draft,
            companyId: companyId,
            financialYearId: financialYearId,
            existingVoucherId: existingVoucherId,
            isSystemReversal: isSystemReversal,
            batchContext: nil
        )
    }

    func validate(_ draft: VoucherDraft,
                  companyId: Company.ID,
                  financialYearId: FinancialYear.ID,
                  existingVoucherId: Voucher.ID? = nil,
                  isSystemReversal: Bool = false,
                  batchContext: BatchContext?) -> ValidationResult {
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

        // A system reversal deliberately mirrors a previously valid voucher.
        // Its cash/bank sides are therefore the inverse of the entry form's
        // single-entry convention, while still requiring all normal balance,
        // fiscal-year, and account checks below.
        if filled.count >= 2 && !isSystemReversal {
            do {
                errors += try singleEntryVoucherErrors(
                    for: draft,
                    companyId: companyId,
                    cashOrBankAccountIDs: batchContext?.cashOrBankAccountIDs
                )
            } catch {
                errors.append(ValidationError(
                    code: .internal,
                    field: "lines",
                    message: "Unable to validate cash/bank eligibility for this voucher."
                ))
            }
        }

        do {
            let fyId: FinancialYear.ID?
            if let batchContext {
                fyId = try batchContext.financialYearId(containing: draft.date)
            } else {
                fyId = try fyIdForDate(draft.date, companyId: companyId)
            }
            if let fyId {
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
            let isLocked: Bool
            if let batchContext {
                isLocked = batchContext.isLocked(financialYearId: financialYearId)
            } else {
                isLocked = try fiscalLockChecker.isLocked(financialYearId: financialYearId)
            }
            if isLocked {
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
                        let isActive: Bool
                        if let batchContext {
                            isActive = batchContext.isAccountActive(acc)
                        } else {
                            isActive = try isAccountActive(acc, companyId: companyId)
                        }
                        if !isActive {
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

    private func singleEntryVoucherErrors(for draft: VoucherDraft,
                                          companyId: Company.ID,
                                          cashOrBankAccountIDs cachedCashOrBankAccountIDs: Set<Account.ID>? = nil) throws -> [ValidationError] {
        guard [.payment, .receipt, .contra].contains(draft.voucherTypeCode) else {
            return []
        }

        let cashOrBankAccountIDs: Set<Account.ID>
        if let cachedCashOrBankAccountIDs {
            cashOrBankAccountIDs = cachedCashOrBankAccountIDs
        } else {
            let accounts = try AccountRepository(db: db).listForCompany(companyId)
            let groups = try AccountGroupRepository(db: db).listForCompany(companyId)
            let groupCodesByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.code) })
            cashOrBankAccountIDs = Set(accounts.lazy.filter {
                isCashOrBank($0, groupCodesByID: groupCodesByID)
            }.map(\.id))
        }
        let lines = draft.filledLines
        let cashOrBankLines = lines.filter {
            $0.accountId.map { cashOrBankAccountIDs.contains($0) } ?? false
        }

        switch draft.voucherTypeCode {
        case .payment, .receipt:
            let accountSide: LedgerSide = draft.voucherTypeCode == .payment ? .credit : .debit
            let particularsSide: LedgerSide = accountSide == .debit ? .credit : .debit
            guard cashOrBankLines.count == 1,
                  cashOrBankLines.first?.side == accountSide,
                  lines.filter({ line in
                      line.accountId.map { !cashOrBankAccountIDs.contains($0) } ?? false
                  }).allSatisfy({ $0.side == particularsSide }) else {
                return [singleEntryValidationError(
                    "Payment requires one cash/bank credit ledger; Receipt requires one cash/bank debit ledger; particulars must be on the opposite side."
                )]
            }
        case .contra:
            let debitCount = lines.filter { $0.side == .debit }.count
            let creditCount = lines.filter { $0.side == .credit }.count
            guard cashOrBankLines.count == lines.count,
                  debitCount == 1,
                  creditCount >= 1 else {
                return [singleEntryValidationError(
                    "Contra vouchers require only cash/bank ledgers, with one destination ledger debited and one or more source ledgers credited."
                )]
            }
        default:
            break
        }

        return []
    }

    private func isCashOrBank(_ account: Account,
                              groupCodesByID: [AccountGroup.ID: String]) -> Bool {
        if account.isBankAccount || account.code == "CASH_IN_HAND" {
            return true
        }
        if account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare("Cash", options: .caseInsensitive) == .orderedSame {
            return true
        }
        guard let groupCode = groupCodesByID[account.groupId] else { return false }
        return ["BANK_ACCOUNTS", "CASH_IN_HAND", "BANK_OD"].contains(groupCode)
    }

    private func singleEntryValidationError(_ message: String) -> ValidationError {
        ValidationError(
            code: .internal,
            field: "lines",
            message: message,
            suggestedFix: "Select cash/bank ledgers only where this voucher type allows them."
        )
    }
}
