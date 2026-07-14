import SwiftUI
import Observation

@MainActor
@Observable
public final class ChequesViewModel {

    public var rows: [AccountingWorkflowsRepository.ChequeRegisterRow] = []
    public var statusFilter: ChequeStatus?
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        do {
            rows = try AccountingWorkflowsRepository(db: db).listCheques(companyId: companyId, status: statusFilter)
            error = nil
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func bounce(voucherId: Voucher.ID, reason: String) {
        do {
            _ = try VoucherService(db: db, companyId: companyId).bounceCheque(voucherId, reason: reason)
            reload()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func represent(voucherId: Voucher.ID, on date: Date) {
        do {
            _ = try VoucherService(db: db, companyId: companyId).representCheque(voucherId, on: date)
            reload()
        } catch {
            self.error = AppError.wrap(error)
        }
    }
}
