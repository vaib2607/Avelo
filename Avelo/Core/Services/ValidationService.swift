import Foundation

public final class ValidationService: Sendable {

    public init() {}

    public func validate(company: CompanyInputValidator.Input) -> ValidationResult {
        CompanyInputValidator().validate(company)
    }

    public func validate(financialYear: FinancialYearInputValidator.Input) -> ValidationResult {
        FinancialYearInputValidator().validate(financialYear)
    }

    public func validate(account: AccountInputValidator.Input,
                         db: SQLiteDatabase,
                         companyId: Company.ID) -> ValidationResult {
        AccountInputValidator(db: db).validate(account, companyId: companyId)
    }

    public func validate(voucherDraft: VoucherDraft,
                         db: SQLiteDatabase,
                         companyId: Company.ID,
                         financialYearId: FinancialYear.ID,
                         existingVoucherId: Voucher.ID? = nil) -> ValidationResult {
        let checker = FiscalLockChecker(db: db)
        return VoucherDraftValidator(db: db, fiscalLockChecker: checker)
            .validate(voucherDraft, companyId: companyId,
                      financialYearId: financialYearId,
                      existingVoucherId: existingVoucherId)
    }

    public func validate(payrollDraft: PayrollDraftValidator.Input) -> ValidationResult {
        PayrollDraftValidator().validate(payrollDraft)
    }

    public func validate(stockMovement: StockMovementValidator.Input) -> ValidationResult {
        StockMovementValidator().validate(stockMovement)
    }

    public static func isValidPAN(_ pan: String) -> Bool {
        CompanyInputValidator.isValidPAN(pan)
    }

    public static func isValidGSTIN(_ gstin: String) -> Bool {
        AccountInputValidator.isValidGSTIN(gstin)
    }
}
