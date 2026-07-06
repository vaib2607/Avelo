import Foundation

public struct FinancialYearOpeningBalanceRepository: Sendable {

    public struct Row: Sendable {
        public let financialYearId: FinancialYear.ID
        public let sourceFinancialYearId: FinancialYear.ID
        public let accountId: Account.ID
        public let openingBalancePaise: Int64
        public let openingBalanceSide: OpeningBalanceSide

        public init(financialYearId: FinancialYear.ID,
                    sourceFinancialYearId: FinancialYear.ID,
                    accountId: Account.ID,
                    openingBalancePaise: Int64,
                    openingBalanceSide: OpeningBalanceSide) {
            self.financialYearId = financialYearId
            self.sourceFinancialYearId = sourceFinancialYearId
            self.accountId = accountId
            self.openingBalancePaise = openingBalancePaise
            self.openingBalanceSide = openingBalanceSide
        }

        public func signedOpeningBalancePaise() throws -> Int64 {
            switch openingBalanceSide {
            case .debit:
                return openingBalancePaise
            case .credit:
                return try CheckedMath.multiply(
                    openingBalancePaise,
                    -1,
                    context: "calculating carried opening balance"
                )
            }
        }
    }

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func listForFinancialYear(_ financialYearId: FinancialYear.ID) throws -> [Row] {
        try db.query(
            """
            SELECT financial_year_id, source_financial_year_id, account_id,
                   opening_balance_paise, opening_balance_side
            FROM avelo_financial_year_opening_balances
            WHERE financial_year_id = ?
            ORDER BY account_id ASC
            """,
            bind: [.text(financialYearId.uuidString)]
        ) { row in
            Row(
                financialYearId: try UUIDParsing.required(
                    row.requiredText("financial_year_id"),
                    field: "avelo_financial_year_opening_balances.financial_year_id"
                ),
                sourceFinancialYearId: try UUIDParsing.required(
                    row.requiredText("source_financial_year_id"),
                    field: "avelo_financial_year_opening_balances.source_financial_year_id"
                ),
                accountId: try UUIDParsing.required(
                    row.requiredText("account_id"),
                    field: "avelo_financial_year_opening_balances.account_id"
                ),
                openingBalancePaise: try row.requiredInt("opening_balance_paise"),
                openingBalanceSide: try row.enumValue("opening_balance_side")
            )
        }
    }

    public func replaceForFinancialYear(_ financialYearId: FinancialYear.ID, rows: [Row]) throws {
        try deleteForFinancialYear(financialYearId)
        guard !rows.isEmpty else { return }
        let now = DateFormatters.formatIsoTimestamp(Date())
        for row in rows {
            try db.execute(
                """
                INSERT INTO avelo_financial_year_opening_balances
                (financial_year_id, source_financial_year_id, account_id,
                 opening_balance_paise, opening_balance_side, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(row.financialYearId.uuidString),
                    .text(row.sourceFinancialYearId.uuidString),
                    .text(row.accountId.uuidString),
                    .integer(row.openingBalancePaise),
                    .text(row.openingBalanceSide.rawValue),
                    .text(now)
                ]
            )
        }
    }

    public func deleteForFinancialYear(_ financialYearId: FinancialYear.ID) throws {
        try db.execute(
            "DELETE FROM avelo_financial_year_opening_balances WHERE financial_year_id = ?",
            [.text(financialYearId.uuidString)]
        )
    }
}
