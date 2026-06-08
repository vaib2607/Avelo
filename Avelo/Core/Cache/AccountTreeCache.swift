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

    public let companyId: Company.ID
    private let database: SQLiteDatabase

    public init(companyId: Company.ID, database: SQLiteDatabase) {
        self.companyId = companyId
        self.database = database
    }

    public func invalidate() {
        isDirty = true
        tree = nil
    }

    public func current() -> AccountTree? { tree }

    public func reload() {
        do {
            isLoading = true
            lastError = nil
            let groups = try AccountGroupRepository(db: database).listForCompany(companyId)
            let ledgers = try AccountRepository(db: database).listForCompany(companyId)
            let balances = try loadLedgerBalances(ledgers: ledgers)
            tree = AccountTree(companyId: companyId,
                               groups: groups,
                               ledgers: ledgers,
                               ledgerBalances: balances)
            isDirty = false
        } catch {
            lastError = AppError.wrap(error)
        }
        isLoading = false
    }

    public func ensureLoaded() -> AccountTree? {
        if isDirty || tree == nil { reload() }
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

    private func loadLedgerBalances(ledgers: [Account]) throws -> [Account.ID: LedgerBalance] {
        guard !ledgers.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ledgers.count).joined(separator: ",")
        let sql = """
            SELECT account_id,
                   COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_ledger_lines
            WHERE account_id IN (\(placeholders))
            GROUP BY account_id
        """
        let binds: [SQLValue] = ledgers.map { .text($0.id.uuidString) }
        var out: [Account.ID: LedgerBalance] = [:]
        _ = try database.query(sql, bind: binds) { row in
            if let idStr = row.optionalText("account_id"), let id = UUID(uuidString: idStr) {
                out[id] = LedgerBalance(
                    debitPaise: row.int("dr"),
                    creditPaise: row.int("cr")
                )
            }
        }
        return out
    }
}
