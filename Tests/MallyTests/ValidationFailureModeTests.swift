import XCTest
@testable import Mally

final class ValidationFailureModeTests: XCTestCase {

    func testAccountValidatorReportsInternalErrorWhenUniquenessQueryFails() {
        let db = try! SQLiteDatabase(path: ":memory:")
        let result = AccountInputValidator(db: db).validate(
            .init(
                code: "LEDGER_1",
                name: "Ledger 1",
                groupId: UUID(),
                openingBalancePaise: 0,
                openingBalanceSide: .debit,
                gstin: nil,
                existingAccountId: nil
            ),
            companyId: UUID()
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { $0.code == .internal }))
    }

    func testVoucherValidatorReportsInternalErrorWhenLookupQueriesFail() {
        let db = try! SQLiteDatabase(path: ":memory:")
        let validator = VoucherDraftValidator(db: db, fiscalLockChecker: FiscalLockChecker(db: db))
        let draft = VoucherDraft(
            mode: .create,
            voucherTypeCode: .journal,
            date: Date(),
            narration: "Test",
            lines: [
                .init(accountId: UUID(), amountPaise: 100, side: .debit),
                .init(accountId: UUID(), amountPaise: 100, side: .credit)
            ]
        )

        let result = validator.validate(
            draft,
            companyId: UUID(),
            financialYearId: UUID()
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { $0.code == .internal }))
    }
}
