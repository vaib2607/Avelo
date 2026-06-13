import Foundation

public struct MigrationV002: Migration {
    public let version: SchemaVersion = .v2
    public let description: String = "Add composite ledger-line index for company/account report and reconciliation queries."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("""
        CREATE INDEX IF NOT EXISTS idx_avelo_lines_company_account_voucher
        ON avelo_ledger_lines(company_id, account_id, voucher_id);
        """)
    }
}
