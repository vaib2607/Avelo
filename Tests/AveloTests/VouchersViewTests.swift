import XCTest
@testable import Avelo

@MainActor
final class VouchersViewTests: XCTestCase {

    func testFilterDateFallbackUsesTodayInsteadOfDistantPast() {
        let fallback = VouchersView.filterDateFallback(nil)
        XCTAssertGreaterThan(fallback.timeIntervalSince1970, 0)
        XCTAssertLessThan(abs(fallback.timeIntervalSinceNow), 5)
    }

    func testFilterDateFallbackPreservesProvidedDate() {
        let date = DateFormatters.parseDate("2024-06-13")!
        XCTAssertEqual(VouchersView.filterDateFallback(date), date)
    }

    func testVoucherCorrectionPolicyUsesEditModeForOpenFinancialYear() {
        let companyId = UUID()
        let financialYear = FinancialYear(
            companyId: companyId,
            label: "2024-25",
            startDate: DateFormatters.parseDate("2024-04-01")!,
            endDate: DateFormatters.parseDate("2025-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2024-04-01")!
        )
        let voucher = Voucher(
            companyId: companyId,
            financialYearId: financialYear.id,
            voucherTypeCode: .journal,
            number: "JRN-0001",
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: nil,
            narration: "Open FY voucher",
            isReversal: false,
            reversalOfId: nil,
            isPosted: true,
            totalPaise: 10_000
        )

        XCTAssertEqual(
            VoucherCorrectionPolicy.mode(for: voucher, financialYear: financialYear),
            .editInPlace
        )
    }

    func testVoucherCorrectionPolicyUsesReversalOnlyForLockedFinancialYear() {
        let companyId = UUID()
        let financialYear = FinancialYear(
            companyId: companyId,
            label: "2024-25",
            startDate: DateFormatters.parseDate("2024-04-01")!,
            endDate: DateFormatters.parseDate("2025-03-31")!,
            booksBeginDate: DateFormatters.parseDate("2024-04-01")!,
            isLocked: true
        )
        let voucher = Voucher(
            companyId: companyId,
            financialYearId: financialYear.id,
            voucherTypeCode: .journal,
            number: "JRN-0001",
            date: DateFormatters.parseDate("2024-06-01")!,
            partyAccountId: nil,
            narration: "Locked FY voucher",
            isReversal: false,
            reversalOfId: nil,
            isPosted: true,
            totalPaise: 10_000
        )

        XCTAssertEqual(
            VoucherCorrectionPolicy.mode(for: voucher, financialYear: financialYear),
            .reversalOnly
        )
    }

}
