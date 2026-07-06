import Foundation

public struct MigrationV013: Migration {
    public let version: SchemaVersion = .v13
    public let description = "Repair legacy payroll employee bank account column drift"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        if try !hasColumn("bank_account_id", in: "avelo_payroll_employees", db: db) {
            try db.execute("ALTER TABLE avelo_payroll_employees ADD COLUMN bank_account_id TEXT REFERENCES avelo_accounts(id);")
        }
    }

    private func hasColumn(_ column: String, in table: String, db: SQLiteDatabase) throws -> Bool {
        let columns: [String] = try db.query("PRAGMA table_info(\(table))") { $0.text("name") }
        return columns.contains(column)
    }
}
