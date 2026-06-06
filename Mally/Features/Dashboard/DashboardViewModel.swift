import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {

    @Published public var companyName: String = ""
    @Published public var fyLabel: String = ""
    @Published public var cashBalancePaise: Int64 = 0
    @Published public var bankBalancePaise: Int64 = 0
    @Published public var receivablesPaise: Int64 = 0
    @Published public var payablesPaise: Int64 = 0
    @Published public var monthSalesPaise: Int64 = 0
    @Published public var monthPurchasesPaise: Int64 = 0
    @Published public var gstPayablePaise: Int64 = 0
    @Published public var stockValuePaise: Int64 = 0
    @Published public var trialBalance: [ReportResult.TrialBalanceRow] = []
    @Published public var monthlyPL: [MonthlyTotal] = []
    @Published public var recentVouchers: [Voucher] = []

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
        companyName = ctx.companyId.uuidString
        fyLabel = ctx.financialYear.label
        let acct = AccountService(db: db, companyId: companyId)
        let report = ReportService(db: db, companyId: companyId)
        let voucherSvc = VoucherService(db: db, companyId: companyId)

        do {
            let groups = try acct.listGroups()
            let accounts = try acct.listAccounts()
            let codes: Set<String> = Set(accounts.map { $0.code })

            func accountId(for code: String) -> Account.ID? {
                accounts.first(where: { $0.code == code })?.id
            }

            if let id = accountId(for: "CASH") {
                let l = try report.ledger(accountId: id, financialYearId: fyId)
                cashBalancePaise = l.closingBalancePaise
            }
            if let id = accountId(for: "BANK") {
                let l = try report.ledger(accountId: id, financialYearId: fyId)
                bankBalancePaise = l.closingBalancePaise
            }
            receivablesPaise = accountId(for: "DEBTORS").map {
                let l = (try? report.ledger(accountId: $0, financialYearId: fyId)) ?? nil
                return l?.closingBalancePaise ?? 0
            } ?? 0
            payablesPaise = accountId(for: "CREDITORS").map {
                let l = (try? report.ledger(accountId: $0, financialYearId: fyId)) ?? nil
                return l?.closingBalancePaise ?? 0
            } ?? 0

            if let id = accountId(for: "GST_OUT") {
                let l = try report.ledger(accountId: id, financialYearId: fyId)
                gstPayablePaise = l.closingBalancePaise
            }

            let stock = try report.stockValuation(asOfDate: Date())
            stockValuePaise = stock.rows.reduce(Int64(0)) { $0 + $1.valuePaise }

            let today = Date()
            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
            if let id = accountId(for: "SALES") {
                let l = try report.ledger(accountId: id, financialYearId: fyId, fromDate: monthStart, toDate: today)
                monthSalesPaise = l.periodCreditPaise
            }
            if let id = accountId(for: "PURCHASES") {
                let l = try report.ledger(accountId: id, financialYearId: fyId, fromDate: monthStart, toDate: today)
                monthPurchasesPaise = l.periodDebitPaise
            }

            trialBalance = try report.trialBalance(asOfDate: today, financialYearId: fyId).rows

            let fy = ctx.financialYear
            let calendar = Calendar.current
            var months: [MonthlyTotal] = []
            var cursor = fy.startDate
            while cursor <= today && cursor <= fy.endDate {
                let comps = calendar.dateComponents([.year, .month], from: cursor)
                let next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                let monthEnd = min(calendar.date(byAdding: .day, value: -1, to: next) ?? cursor, today)
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
            _ = groups
            _ = codes
        } catch {
            // soft-fail; dashboard shows whatever was loaded before
        }
    }
}
