import SwiftUI

@MainActor
public final class VouchersViewModel: ObservableObject {

    @Published public var vouchers: [Voucher] = []
    @Published public var accounts: [Account] = []
    @Published public var filter: VoucherRepository.Filter
    @Published public var query: String = ""
    @Published public var typeFilter: Set<VoucherType.Code> = []
    @Published public var fromDate: Date?
    @Published public var toDate: Date?
    @Published public var isLoading: Bool = false
    @Published public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID?

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID?) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
        self.filter = VoucherRepository.Filter(companyId: companyId, financialYearId: fyId)
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            let svc = VoucherService(db: db, companyId: companyId)
            let acct = AccountService(db: db, companyId: companyId)
            var f = filter
            f.companyId = companyId
            f.financialYearId = fyId
            f.fromDate = fromDate
            f.toDate = toDate
            f.voucherTypeCodes = typeFilter
            f.searchText = query.isEmpty ? nil : query
            vouchers = try svc.list(filter: f)
            accounts = try acct.listActiveAccounts()
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func accountName(_ id: Account.ID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? id.uuidString.prefix(8) + "…"
    }
}
