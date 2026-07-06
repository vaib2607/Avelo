import Foundation

public struct MigrationV008: Migration {
    public let version: SchemaVersion = .v8
    public let description = "Backfill deterministic GST round-off ledger"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        let rows: [(companyId: String, groupId: String)] = try db.query(
            """
            SELECT g.company_id AS company_id, g.id AS group_id
            FROM avelo_account_groups g
            WHERE g.code = 'INDIRECT_EXPENSE'
              AND NOT EXISTS (
                SELECT 1
                FROM avelo_accounts a
                WHERE a.company_id = g.company_id
                  AND a.code = 'ROUND_OFF'
              )
            """
        ) {
            (companyId: $0.text("company_id"), groupId: $0.text("group_id"))
        }

        for row in rows {
            let now = Date()
            try db.execute(
                """
                INSERT INTO avelo_accounts
                (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                 is_active, is_bank_account, created_at, updated_at)
                VALUES (?, ?, ?, 'ROUND_OFF', 'Round Off', 0, 'debit', 1, 0, ?, ?)
                """,
                [
                    .text(UUID().uuidString),
                    .text(row.companyId),
                    .text(row.groupId),
                    .timestamp(now),
                    .timestamp(now)
                ]
            )
        }
    }
}
