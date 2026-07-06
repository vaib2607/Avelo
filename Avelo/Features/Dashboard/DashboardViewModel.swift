import SwiftUI
import Observation

@MainActor
@Observable
public final class DashboardViewModel {

    public var companyName: String = ""
    public var fyLabel: String = ""
    public var cashBalancePaise: Int64 = 0
    public var bankBalancePaise: Int64 = 0
    public var receivablesPaise: Int64 = 0
    public var payablesPaise: Int64 = 0
    public var monthSalesPaise: Int64 = 0
    public var monthPurchasesPaise: Int64 = 0
    public var gstPayablePaise: Int64 = 0
    public var stockValuePaise: Int64 = 0
    public var trialBalance: [ReportResult.TrialBalanceRow] = []
    public var monthlyPL: [MonthlyTotal] = []
    public var recentVouchers: [Voucher] = []

    public init() {}

    public struct MonthlyTotal: Identifiable, Sendable {
        public let id = UUID()
        public let monthLabel: String
        public let incomePaise: Int64
        public let expensePaise: Int64
    }

    public func reload(ctx: CompanyContext) {
        let db = ctx.database
        let companyId = ctx.companyId
        let fyId = ctx.financialYear.id
        companyName = ctx.companyName
        fyLabel = ctx.financialYear.label
        let acct = AccountService(db: db, companyId: companyId)
        let report = ReportService(db: db, companyId: companyId)
        let voucherSvc = VoucherService(db: db, companyId: companyId)

        do {
            let accounts = try acct.listAccounts()
            let today = Date()
            let reportEndDate = min(today, ctx.financialYear.endDate)

            func accountId(for code: String) -> Account.ID? {
                accounts.first(where: { $0.code == code })?.id
            }

            if let id = accountId(for: "CASH_IN_HAND") {
                let l = try report.ledger(accountId: id, financialYearId: fyId)
                cashBalancePaise = l.closingBalancePaise
            }
            bankBalancePaise = 0
            for bankAccount in accounts where bankAccount.isBankAccount {
                let ledger = try report.ledger(accountId: bankAccount.id, financialYearId: fyId)
                bankBalancePaise = try CheckedMath.add(
                    bankBalancePaise,
                    ledger.closingBalancePaise,
                    context: "summing dashboard bank balances"
                )
            }
            receivablesPaise = try report.outstanding(asOfDate: reportEndDate, direction: .receivables).totalPaise
            payablesPaise = try report.outstanding(asOfDate: reportEndDate, direction: .payables).totalPaise

            let gst = try report.gstSummary(fromDate: ctx.financialYear.startDate, toDate: reportEndDate)
            gstPayablePaise = gst.netPayablePaise

            let stock = try report.stockValuation(asOfDate: reportEndDate)
            stockValuePaise = try CheckedMath.sum(stock.rows.map(\.valuePaise), context: "summing dashboard stock value")

            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
            if let id = accountId(for: "SALES") {
                let l = try report.ledger(accountId: id, financialYearId: fyId, fromDate: monthStart, toDate: reportEndDate)
                monthSalesPaise = l.periodCreditPaise
            }
            if let id = accountId(for: "PURCHASE") {
                let l = try report.ledger(accountId: id, financialYearId: fyId, fromDate: monthStart, toDate: reportEndDate)
                monthPurchasesPaise = l.periodDebitPaise
            }

            trialBalance = try report.trialBalance(asOfDate: reportEndDate, financialYearId: fyId).rows

            let fy = ctx.financialYear
            let calendar = Calendar.current
            var months: [MonthlyTotal] = []
            var cursor = fy.startDate
            while cursor <= reportEndDate && cursor <= fy.endDate {
                let comps = calendar.dateComponents([.year, .month], from: cursor)
                let next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                let monthEnd = min(calendar.date(byAdding: .day, value: -1, to: next) ?? cursor, reportEndDate)
                if let id = accountId(for: "SALES") {
                    let l = try report.ledger(accountId: id, financialYearId: fyId, fromDate: cursor, toDate: monthEnd)
                    let exp = try report.profitAndLoss(fromDate: cursor, toDate: monthEnd, financialYearId: fyId)
                    let label = String(format: "%02d/%d", comps.month ?? 1, comps.year ?? 1)
                    months.append(MonthlyTotal(
                        monthLabel: label,
                        incomePaise: l.periodCreditPaise,
                        expensePaise: exp.totalExpensesPaise
                    ))
                }
                cursor = next
            }
            monthlyPL = months

            let f = VoucherRepository.Filter(companyId: companyId, financialYearId: fyId, limit: 10)
            recentVouchers = try voucherSvc.list(filter: f)
        } catch {
            // soft-fail; dashboard shows whatever was loaded before
        }
    }
}
