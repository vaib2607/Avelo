import Foundation

public struct AccountingWorkflowsRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func deleteForVoucher(_ voucherId: Voucher.ID) throws {
        _ = voucherId
        throw AppError.featureUnavailable("Bill, cheque, TDS, and TCS workflows are deferred outside the frozen schema.")
    }

    public func workflowInputs(for voucherId: Voucher.ID) throws -> VoucherService.WorkflowInputs {
        _ = voucherId
        return VoucherService.WorkflowInputs()
    }

    public func insert(_ a: BillAllocation) throws {
        _ = a
        throw AppError.featureUnavailable("Bill allocations are deferred outside the frozen schema.")
    }

    public func insert(_ c: Cheque) throws {
        _ = c
        throw AppError.featureUnavailable("Cheque workflows are deferred outside the frozen schema.")
    }

    public func insert(_ r: TDSRecord) throws {
        _ = r
        throw AppError.featureUnavailable("TDS workflows are deferred outside the frozen schema.")
    }

    public func insert(_ r: TCSRecord) throws {
        _ = r
        throw AppError.featureUnavailable("TCS workflows are deferred outside the frozen schema.")
    }
}
