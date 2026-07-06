import Foundation

public struct MigrationV011: Migration {

    public let version: SchemaVersion = .v11
    public let description: String = "Expand fiscal-lock enforcement to stock, payroll, banking, opening balances, and voucher updates."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        for triggerName in RestoreService.lockedFinancialYearTriggerNamesForMigration {
            try db.execute("DROP TRIGGER IF EXISTS \(triggerName)")
        }
        for sql in RestoreService.lockedFinancialYearTriggerSQLForMigration {
            try db.execute(sql)
        }
    }
}
