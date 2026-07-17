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
<<<<<<< HEAD
    public var pagination = PaginationState()
    public var isLoading: Bool = false
    public var error: AppError?
    public var selectedVoucherId: Voucher.ID?

    public var limit: Int {
        get { pagination.limit }
        set { pagination.limit = max(1, newValue) }
    }

    public var offset: Int {
        get { pagination.offset }
        set { pagination.offset = max(0, newValue) }
    }
=======
    public var isLoading: Bool = false
    public var error: AppError?
>>>>>>> origin/main

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID?
<<<<<<< HEAD
    internal var onResultsReady: (@Sendable () async -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration: UUID = UUID()
=======
>>>>>>> origin/main

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID?) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
        self.filter = VoucherRepository.Filter(companyId: companyId, financialYearId: fyId)
    }

    public func reload() {
        isLoading = true
<<<<<<< HEAD
        reloadTask?.cancel()
        let generation = UUID()
        reloadGeneration = generation
        error = nil
=======
>>>>>>> origin/main
        let db = db
        let companyId = companyId
        let fyId = fyId
        let fromDate = fromDate
        let toDate = toDate
<<<<<<< HEAD
        let limit = limit
        let offset = offset
        let typeFilter = typeFilter
        let query = query
        let baseFilter = filter
        reloadTask = Task.detached { [weak self] in
=======
        let typeFilter = typeFilter
        let query = query
        let baseFilter = filter
        Task.detached {
>>>>>>> origin/main
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
<<<<<<< HEAD
                f.limit = limit
                f.offset = offset
                let vouchers = try svc.list(filter: f)
                let totalCount = try svc.count(filter: f)
                let accounts = try acct.listActiveAccounts()
                await self?.onResultsReady?()
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
                    self.vouchers = vouchers
                    self.accounts = accounts
                    self.pagination.totalCount = totalCount
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.reloadGeneration == generation, !Task.isCancelled else { return }
=======
                let vouchers = try svc.list(filter: f)
                let accounts = try acct.listActiveAccounts()
                await MainActor.run {
                    self.vouchers = vouchers
                    self.accounts = accounts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
>>>>>>> origin/main
                    self.error = AppError.wrap(error)
                    self.isLoading = false
                }
            }
        }
    }

<<<<<<< HEAD
    public func reloadFirstPage() {
        pagination.reset()
        reload()
    }

    public func previousPage() {
        pagination.goPrevious()
        reload()
    }

    public func nextPage() {
        pagination.goNext()
        reload()
    }

    /// AVL-P2-013 (PgUp/PgDn): moves selection within the currently loaded
    /// page only — does not cross pages, matching the plain lazy scope of
    /// "continuous browsing" without adding auto-pagination.
    public func selectPrevious() {
        move(by: -1)
    }

    public func selectNext() {
        move(by: 1)
    }

    private func move(by delta: Int) {
        guard !vouchers.isEmpty else { return }
        guard let current = selectedVoucherId, let index = vouchers.firstIndex(where: { $0.id == current }) else {
            selectedVoucherId = delta > 0 ? vouchers.first?.id : vouchers.last?.id
            return
        }
        let newIndex = index + delta
        guard vouchers.indices.contains(newIndex) else { return }
        selectedVoucherId = vouchers[newIndex].id
    }

    public func accountName(_ id: Account.ID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? id.uuidString.prefix(8) + "…"
    }

    /// Renders a GST tax invoice PDF for a Sales/Purchase voucher
    /// (AVL-P0-022). The view owns the save panel; this just produces the
    /// bytes to write.
    public func invoicePDFData(voucherId: Voucher.ID) throws -> Data {
        try InvoicePDFService(db: db).exportTaxInvoicePDF(voucherId: voucherId)
    }

    public func recordInvoicePDFSaved(voucherId: Voucher.ID, url: URL) throws {
        try InvoicePDFService(db: db).recordExportSaved(voucherId: voucherId, url: url)
    }
=======
    public func accountName(_ id: Account.ID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? id.uuidString.prefix(8) + "…"
    }
>>>>>>> origin/main
}
