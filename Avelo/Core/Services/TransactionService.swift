import Foundation

public final class TransactionService: Sendable {

    public let voucherService: VoucherService

    public init(voucherService: VoucherService) {
        self.voucherService = voucherService
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear) async throws -> Voucher {
        let result = try voucherService.post(draft: draft, in: fy)
        return result.voucher
    }
}
