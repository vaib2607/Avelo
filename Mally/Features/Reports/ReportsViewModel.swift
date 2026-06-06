import SwiftUI

@MainActor
public final class ReportsViewModel: ObservableObject {

    @Published public var selection: ReportSelection = .trialBalance
    @Published public var fromDate: Date = Date()
    @Published public var toDate: Date = Date()
    @Published public var asOf: Date = Date()
    @Published public var trialBalance: [ReportResult.TrialBalanceRow] = []
    @Published public var profitLoss: ReportResult.ProfitLoss?
    @Published public var balanceSheet: ReportResult.BalanceSheet?
    @Published public var gstSummary: ReportResult.GstSummary?
    @Published public var dayBook: [ReportResult.DayBookRow] = []
    @Published public var ledger: ReportResult.LedgerReport?
    @Published public var outstanding: ReportResult.OutstandingReport?
    @Published public var stockValuation: ReportResult.StockValuationReport?
    @Published public var ledgerAccountId: Account.ID?
    @Published public var accounts: [Account] = []
    @Published public var isLoading: Bool = false
    @Published public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID?

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID?) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            let svc = ReportService(db: db, companyId: companyId)
            accounts = try AccountService(db: db, companyId: companyId).listActiveAccounts()
            switch selection {
            case .trialBalance:
                trialBalance = try svc.trialBalance(asOfDate: asOf, financialYearId: fyId).rows
            case .profitLoss:
                profitLoss = try svc.profitAndLoss(fromDate: fromDate, toDate: toDate, financialYearId: fyId)
            case .balanceSheet:
                balanceSheet = try svc.balanceSheet(asOfDate: asOf, financialYearId: fyId)
            case .gstSummary:
                gstSummary = try svc.gstSummary(fromDate: fromDate, toDate: toDate)
            case .dayBook:
                dayBook = try svc.dayBook(fromDate: fromDate, toDate: toDate)
            case .ledger:
                if let aid = ledgerAccountId {
                    ledger = try svc.ledger(accountId: aid, financialYearId: fyId, fromDate: fromDate, toDate: toDate)
                } else {
                    ledger = nil
                }
            case .outstanding:
                outstanding = try svc.outstanding(asOfDate: asOf, direction: .receivable)
            case .stockValuation:
                stockValuation = try svc.stockValuation(asOfDate: asOf)
            }
        } catch {
            self.error = AppError.wrap(error)
        }
    }
}
