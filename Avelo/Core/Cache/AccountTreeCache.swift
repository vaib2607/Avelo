import Foundation
import Observation

/// Threadsafe lazy cache for the per-company `AccountTree`.
///
/// Marks itself dirty on `invalidate()`; rebuilds on next access.
/// All public accessors are `@MainActor` because the underlying tree is
/// observed by SwiftUI views.
@MainActor
@Observable
public final class AccountTreeCache {

    public private(set) var tree: AccountTree?
    public private(set) var isDirty: Bool = true
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: AppError?
    internal var onBackgroundLoad: (@Sendable (Bool) -> Void)?

    public let companyId: Company.ID
    private let database: SQLiteDatabase
    public var financialYearId: FinancialYear.ID?

    public init(companyId: Company.ID, database: SQLiteDatabase, financialYearId: FinancialYear.ID? = nil) {
        self.companyId = companyId
        self.database = database
        self.financialYearId = financialYearId
    }

    public func invalidate() {
        isDirty = true
        tree = nil
    }

    public func current() -> AccountTree? { tree }

    public func reload() async {
        do {
            isLoading = true
            lastError = nil
            let database = database
            let companyId = companyId
            let financialYearId = financialYearId
            let probe = onBackgroundLoad
            let tree = try await Task.detached(priority: .userInitiated) { () throws -> AccountTree in
                try database.read { tx in
                    probe?(Thread.isMainThread)
                    let groups = try AccountGroupRepository(db: tx).listForCompany(companyId)
                    let ledgers = try AccountRepository(db: tx).listForCompany(companyId)
                    let reportRepository = ReportRepository(db: tx)
                    let filter = ReportResult.ReportFilter(companyId: companyId, financialYearId: financialYearId)
                    let openingContext = try reportRepository.financialYearOpeningContext(filter: filter)
                    let balances = try Self.loadLedgerBalances(
                        db: tx,
                        financialYearId: financialYearId,
                        fromDate: openingContext?.financialYear.startDate,
                        ledgers: ledgers
                    )
                    let openingOverrides = try Dictionary(uniqueKeysWithValues: ledgers.map { ledger in
                        (
                            ledger.id,
                            try reportRepository.signedOpeningBalance(
                                for: ledger,
                                filter: filter,
                                openingContext: openingContext
                            )
                        )
                    })
                    return try AccountTree(companyId: companyId,
                                           groups: groups,
                                           ledgers: ledgers,
                                           ledgerBalances: balances,
                                           openingBalanceOverrides: openingOverrides)
                }
            }.value
            self.tree = tree
            isDirty = false
        } catch {
            lastError = AppError.wrap(error)
        }
        isLoading = false
    }

    public func ensureLoaded() -> AccountTree? {
        if isLoading {
            return tree
        }
        if isDirty || tree == nil {
            isLoading = true
            Task { await reload() }
        }
        return tree
    }

    public func findLedger(_ id: Account.ID) -> LedgerNode? {
        ensureLoaded()?.findLedger(id)
    }

    public func findGroup(_ id: AccountGroup.ID) -> GroupNode? {
        ensureLoaded()?.findGroup(id)
    }

    public func breadcrumb(of ledgerId: Account.ID) -> String {
        ensureLoaded()?.breadcrumb(of: ledgerId) ?? ""
    }

    nonisolated private static func loadLedgerBalances(db: SQLiteDatabase,
                                                       financialYearId: FinancialYear.ID?,
                                                       fromDate: Date?,
                                                       ledgers: [Account]) throws -> [Account.ID: LedgerBalance] {
        guard !ledgers.isEmpty else { return [:] }
        var out: [Account.ID: LedgerBalance] = [:]
        let batchSize = 500
        let fyEnd: Date? = {
            guard let financialYearId else {
                return nil
            }
            do {
                return try FinancialYearRepository(db: db).findById(financialYearId)?.endDate
            } catch {
                return nil
            }
        }()
        var index = ledgers.startIndex
        while index < ledgers.endIndex {
            let end = ledgers.index(index, offsetBy: batchSize, limitedBy: ledgers.endIndex) ?? ledgers.endIndex
            let batch = ledgers[index..<end]
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            var sql = """
                SELECT l.account_id,
                       COALESCE(SUM(CASE WHEN l.side='debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                       COALESCE(SUM(CASE WHEN l.side='credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
                FROM trn_accounting_compat l
                JOIN avelo_vouchers v ON v.id = l.voucher_id
                WHERE l.account_id IN (\(placeholders))
            """
            var binds: [SQLValue] = batch.map { .text($0.id.uuidString) }
            if let to = fyEnd {
                sql += " AND v.date <= ?"
                binds.append(.date(to))
            }
            if let fromDate {
                sql += " AND v.date >= ?"
                binds.append(.date(fromDate))
            }
            sql += " GROUP BY l.account_id"
            _ = try db.query(sql, bind: binds) { row in
                if let idStr = row.optionalText("account_id"), let id = UUID(uuidString: idStr) {
                    let debit = row.int("dr")
                    let credit = row.int("cr")
                    out[id] = LedgerBalance(
                        debitPaise: debit,
                        creditPaise: credit
                    )
                }
            }
            index = end
        }
        return out
    }
}
