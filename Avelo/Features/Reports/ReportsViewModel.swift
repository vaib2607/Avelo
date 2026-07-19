import SwiftUI
import Observation

public enum BalanceSheetRequestError: Error, Equatable, Sendable {
    case primary(AppError)
    case comparative(AppError)

    public var underlyingError: AppError {
        switch self {
        case let .primary(error), let .comparative(error): return error
        }
    }

    public var periodName: String {
        switch self {
        case .primary: return "Primary period"
        case .comparative: return "Comparison period"
        }
    }
}

@MainActor
@Observable
public final class ReportsViewModel {

    public var selection: ReportSelection = .trialBalance
    public var fromDate: Date = Date()
    public var toDate: Date = Date()
    public var asOf: Date = Date()
    public var trialBalance: [ReportResult.TrialBalanceRow] = []
    public var profitLoss: ReportResult.ProfitLoss?
    public var balanceSheet: ReportResult.BalanceSheet?
    public var gstSummary: ReportResult.GstSummary?
    public var dayBook: [ReportResult.DayBookRow] = []
    public var selectedDay: Date = Date()
    public var selectedDayBookVoucherId: Voucher.ID?
    public var dayBookError: AppError?
    public var ledger: ReportResult.LedgerReport?
    public var outstanding: ReportResult.OutstandingReport?
    public var stockValuation: ReportResult.StockValuationReport?
    public var cashFlow: ReportResult.CashFlowStatement?
    public var stockAgeing: ReportResult.StockAgeingReport?
    public var stockMovements: [StockMovement] = []
    public var stockRegisterRows: [StockRegisterRow] = []
    public var ledgerAccountId: Account.ID?
    public var cashBankAccountId: Account.ID?
    public var accounts: [Account] = []
    public var cashBankAccounts: [Account] = []
    public var isLoading: Bool = false
    public var error: AppError?
    public var balanceSheetRequestError: BalanceSheetRequestError?
    public var balanceSheetErrorFinancialYearId: FinancialYear.ID?
    public var balanceSheetErrorAsOf: Date?

    // AVL-P1-036 (Alt+N comparative columns): prior-year-same-period column
    // for the three point-in-time/range statements. Reuses the same
    // ReportService calls with a one-year-back date shift — no separate
    // report math, so it can't drift from the primary column's numbers.
    public var comparativeEnabled: Bool = false
    /// AVL-P1-036: which offset the comparative column uses. Defaults to
    /// prior-year, reproducing the previously-hardcoded behavior exactly.
    public var comparativePeriod: ComparativePeriod = .priorYear
    public var comparativeTrialBalance: [ReportResult.TrialBalanceRow] = []
    public var comparativeProfitLoss: ReportResult.ProfitLoss?
    public var comparativeBalanceSheet: ReportResult.BalanceSheet?
    public var comparativeColumnLabel: String { comparativeEnabled ? comparativePeriod.columnLabel : "" }

    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public private(set) var fyId: FinancialYear.ID?

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID?) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
    }

    public func reload() {
        guard selection != .balanceSheet else {
            loadBalanceSheet()
            return
        }
        guard selection != .dayBook else {
            loadDayBook(day: selectedDay)
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let svc = ReportService(db: db, companyId: companyId)
            accounts = try AccountService(db: db, companyId: companyId).listActiveAccounts()
            guard let company = try CompanyRepository(db: db).findById(companyId) else {
                throw AppError.notFound("Company")
            }
            if selection.requiresInventory && !company.isInventoryEnabled {
                throw AppError.featureUnavailable("Inventory is disabled for this company.")
            }
            let groups = try AccountGroupRepository(db: db).listForCompany(companyId)
            let policy = try AccountEligibilityPolicy.loading(db: db, companyId: companyId)
            cashBankAccounts = accounts.filter {
                policy.evaluate(account: $0, for: .bankReconciliation, company: company, groups: groups).isEligible
            }
            switch selection {
            case .trialBalance:
                // Compute both periods before publishing either: a comparative
                // failure must not leave a fresh primary column next to a
                // stale comparative one from the previous scope (same atomic
                // publish contract as loadBalanceSheet).
                let primaryTrialBalance = try svc.trialBalance(asOfDate: asOf, financialYearId: fyId).rows
                let comparativeTrialBalanceRows = try comparativeEnabled
                    ? svc.trialBalance(asOfDate: comparativePeriod.shift(asOf), financialYearId: financialYearID(containing: comparativePeriod.shift(asOf))).rows
                    : []
                trialBalance = primaryTrialBalance
                comparativeTrialBalance = comparativeTrialBalanceRows
            case .profitLoss:
                let primaryProfitLoss = try svc.profitAndLoss(fromDate: fromDate, toDate: toDate, financialYearId: fyId)
                let comparativeProfitLossResult = try comparativeEnabled
                    ? svc.profitAndLoss(
                        fromDate: comparativePeriod.shift(fromDate),
                        toDate: comparativePeriod.shift(toDate),
                        financialYearId: financialYearID(containing: comparativePeriod.shift(fromDate))
                    )
                    : nil
                profitLoss = primaryProfitLoss
                comparativeProfitLoss = comparativeProfitLossResult
            case .balanceSheet:
                break
            case .gstSummary:
                gstSummary = try svc.gstSummary(fromDate: fromDate, toDate: toDate)
            case .dayBook:
                break
            case .ledger:
                if let aid = ledgerAccountId {
                    ledger = try svc.ledger(accountId: aid, financialYearId: fyId, fromDate: fromDate, toDate: toDate)
                } else {
                    ledger = nil
                }
            case .cashBook, .bankBook:
                if cashBankAccountId == nil {
                    cashBankAccountId = cashBankAccounts.first?.id
                }
                if let aid = cashBankAccountId {
                    ledger = try svc.ledger(accountId: aid, financialYearId: fyId, fromDate: fromDate, toDate: toDate)
                } else {
                    ledger = nil
                }
            case .receivables:
                outstanding = try svc.outstanding(asOfDate: asOf, direction: .receivables)
            case .payables:
                outstanding = try svc.outstanding(asOfDate: asOf, direction: .payables)
            case .stockMovement, .stockRegister:
                let inventory = InventoryRepository(db: db)
                stockMovements = try inventory.listMovements(filter: .init(companyId: companyId, fromDate: fromDate, toDate: toDate))
                if selection == .stockRegister {
                    let items = try inventory.listItemsForCompany(companyId, includeInactive: true)
                    let itemNames = Dictionary(uniqueKeysWithValues: items.map { ($0.id, "\($0.code) — \($0.name)") })
                    stockRegisterRows = stockMovements.map { movement in
                        StockRegisterRow(
                            itemId: movement.itemId,
                            itemName: itemNames[movement.itemId] ?? movement.itemId.uuidString,
                            movement: movement
                        )
                    }
                    .sorted {
                        if $0.itemName == $1.itemName {
                            return $0.movement.date > $1.movement.date
                        }
                        return $0.itemName < $1.itemName
                    }
                } else {
                    stockRegisterRows = []
                }
            case .gstFiling:
                gstSummary = try svc.gstSummary(fromDate: fromDate, toDate: toDate)
            case .outstanding:
                outstanding = try svc.outstanding(asOfDate: asOf, direction: .receivables)
            case .stockValuation:
                stockValuation = try svc.stockValuation(asOfDate: asOf)
            case .cashFlow:
                cashFlow = try svc.cashFlow(fromDate: fromDate, toDate: toDate)
            case .stockAgeing:
                stockAgeing = try svc.stockAgeing(asOfDate: asOf)
            }
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    public func toggleComparative() {
        comparativeEnabled.toggle()
        reload()
    }

    /// Applies one settled FY transition.  The view owns observing environment
    /// changes; this model owns clearing old scoped results before exactly one
    /// reload of the currently selected report.
    public func resetFinancialYear(_ financialYear: FinancialYear) {
        guard financialYear.companyId == companyId, fyId != financialYear.id else { return }
        fyId = financialYear.id
        fromDate = financialYear.startDate
        toDate = financialYear.endDate
        asOf = financialYear.endDate
        selectedDay = financialYear.startDate
        balanceSheet = nil
        comparativeBalanceSheet = nil
        balanceSheetRequestError = nil
        balanceSheetErrorFinancialYearId = nil
        balanceSheetErrorAsOf = nil
        error = nil
        reload()
    }

    private func loadBalanceSheet() {
        isLoading = true
        balanceSheet = nil
        comparativeBalanceSheet = nil
        error = nil
        balanceSheetRequestError = nil
        balanceSheetErrorFinancialYearId = fyId
        balanceSheetErrorAsOf = asOf
        defer { isLoading = false }
        do {
            let service = ReportService(db: db, companyId: companyId)
            let primaryScope = try service.balanceSheetScope(asOfDate: asOf, financialYearId: fyId)
            var comparativeScope: BalanceSheetScope?
            if comparativeEnabled {
                let comparativeAsOf = comparativePeriod.shift(asOf)
                do {
                    balanceSheetErrorFinancialYearId = nil
                    balanceSheetErrorAsOf = comparativeAsOf
                    let comparativeFYId = try financialYearID(containing: comparativeAsOf)
                    balanceSheetErrorFinancialYearId = comparativeFYId
                    balanceSheetErrorAsOf = comparativeAsOf
                    comparativeScope = try service.balanceSheetScope(asOfDate: comparativeAsOf, financialYearId: comparativeFYId)
                } catch {
                    throw BalanceSheetRequestError.comparative(AppError.wrap(error))
                }
            }
            // Both requested periods now have valid explicit scopes. Only then
            // may either candidate perform cache/reconciliation/report reads.
            let primary = try service.balanceSheet(scope: primaryScope)
            let comparative = try comparativeScope.map { try service.balanceSheet(scope: $0) }
            // Publish only a fully verified primary/comparison pair.
            balanceSheet = primary
            comparativeBalanceSheet = comparative
            balanceSheetErrorFinancialYearId = nil
            balanceSheetErrorAsOf = nil
        } catch let requestError as BalanceSheetRequestError {
            balanceSheetRequestError = requestError
            self.error = requestError.underlyingError
            balanceSheet = nil
            comparativeBalanceSheet = nil
        } catch {
            let requestError = BalanceSheetRequestError.primary(AppError.wrap(error))
            balanceSheetRequestError = requestError
            self.error = requestError.underlyingError
            balanceSheet = nil
            comparativeBalanceSheet = nil
        }
    }

    public func loadDayBook(day: Date) {
        isLoading = true
        dayBook = []
        dayBookError = nil
        error = nil
        defer { isLoading = false }
        do {
            let rows = try ReportService(db: db, companyId: companyId).dayBook(fromDate: day, toDate: day)
            dayBook = rows
            if let selectedDayBookVoucherId,
               !rows.contains(where: { $0.id == selectedDayBookVoucherId }) {
                self.selectedDayBookVoucherId = nil
            }
        } catch {
            dayBookError = AppError.wrap(error)
            dayBook = []
        }
    }

    public func previousDay() {
        selectedDay = DateFormatters.utcCalendar.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
        loadDayBook(day: selectedDay)
    }

    public func nextDay() {
        selectedDay = DateFormatters.utcCalendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        loadDayBook(day: selectedDay)
    }

    private func financialYearID(containing date: Date) throws -> FinancialYear.ID {
        let matches = try FinancialYearRepository(db: db).containing(date: date, companyId: companyId)
        guard matches.count == 1, let financialYear = matches.first else {
            throw AppError.validation(.init(
                code: .reportFinancialYearMissing,
                field: "asOfDate",
                message: "No unique financial year contains the comparative Balance Sheet date.",
                suggestedFix: "Create or select the financial year containing \(DateFormatters.formatIsoDate(date))."
            ))
        }
        return financialYear.id
    }

}

public struct StockRegisterRow: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let itemId: InventoryItem.ID
    public let itemName: String
    public let movement: StockMovement
}
