import SwiftUI
import Observation

@MainActor
@Observable
public final class VouchersViewModel {

    public var vouchers: [Voucher] = []
    public var accounts: [Account] = []
    public var filter: VoucherRepository.Filter
    public var query: String = ""
    public var typeFilter: Set<VoucherType.Code> = []
    public var fromDate: Date?
    public var toDate: Date?
    public var limit: Int = 200
    public var offset: Int = 0
    public var isLoading: Bool = false
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID?
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID?) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
        self.filter = VoucherRepository.Filter(companyId: companyId, financialYearId: fyId)
    }

    public func reload() {
        isLoading = true
        reloadTask?.cancel()
        let generation = UUID()
        reloadGeneration = generation
        error = nil
        let db = db
        let companyId = companyId
        let fyId = fyId
        let fromDate = fromDate
        let toDate = toDate
        let limit = limit
        let offset = offset
        let typeFilter = typeFilter
        let query = query
        let baseFilter = filter
        reloadTask = Task.detached { [weak self] in
            do {
                let svc = VoucherService(db: db, companyId: companyId)
                let acct = AccountService(db: db, companyId: companyId)
                var f = baseFilter
                f.companyId = companyId
                f.financialYearId = fyId
                f.fromDate = fromDate
                f.toDate = toDate
                f.voucherTypeCodes = typeFilter
                f.searchText = query.isEmpty ? nil : query
                f.limit = limit
                f.offset = offset
                let vouchers = try svc.list(filter: f)
                let accounts = try acct.listActiveAccounts()
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.vouchers = vouchers
                    self.accounts = accounts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

    public func accountName(_ id: Account.ID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? id.uuidString.prefix(8) + "…"
    }
}
