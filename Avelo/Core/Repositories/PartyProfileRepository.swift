import Foundation

public struct PartyProfileRepository: Sendable {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func find(accountId: Account.ID, companyId: Company.ID) throws -> PartyProfile? {
        try db.queryOne(
            """
            SELECT account_id, company_id, usage, credit_limit_paise,
                   default_credit_period_days, maintain_billwise, created_at, updated_at
            FROM avelo_party_profiles
            WHERE account_id = ? AND company_id = ?
            """,
            bind: [.text(accountId.uuidString), .text(companyId.uuidString)],
            row: Self.rowToProfile
        )
    }

    public func list(companyId: Company.ID) throws -> [PartyProfile] {
        try db.query(
            """
            SELECT account_id, company_id, usage, credit_limit_paise,
                   default_credit_period_days, maintain_billwise, created_at, updated_at
            FROM avelo_party_profiles
            WHERE company_id = ?
            ORDER BY account_id
            """,
            bind: [.text(companyId.uuidString)],
            row: Self.rowToProfile
        )
    }

    public func usageByAccountId(companyId: Company.ID) throws -> [Account.ID: PartyUsage] {
        Dictionary(uniqueKeysWithValues: try list(companyId: companyId).map { ($0.accountId, $0.usage) })
    }

    public func upsert(_ profile: PartyProfile) throws {
        guard profile.creditLimitPaise.map({ $0 >= 0 }) ?? true,
              profile.defaultCreditPeriodDays.map({ $0 >= 0 }) ?? true else {
            throw AppError.validation(.init(code: .internal, field: "partyProfile", message: "Party credit values cannot be negative."))
        }
        try db.execute(
            """
            INSERT INTO avelo_party_profiles
            (account_id, company_id, usage, credit_limit_paise, default_credit_period_days,
             maintain_billwise, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id) DO UPDATE SET
                usage = excluded.usage,
                credit_limit_paise = excluded.credit_limit_paise,
                default_credit_period_days = excluded.default_credit_period_days,
                maintain_billwise = excluded.maintain_billwise,
                updated_at = excluded.updated_at
            """,
            [
                .text(profile.accountId.uuidString),
                .text(profile.companyId.uuidString),
                .text(profile.usage.rawValue),
                .optionalInteger(profile.creditLimitPaise),
                .optionalInteger(profile.defaultCreditPeriodDays.map(Int64.init)),
                .bool(profile.maintainBillwise),
                .timestamp(profile.createdAt),
                .timestamp(profile.updatedAt)
            ]
        )
    }

    private static func rowToProfile(_ row: Row) throws -> PartyProfile {
        let usage = try row.enumValue("usage", as: PartyUsage.self)
        let creditDays = try row.checkedOptionalInt("default_credit_period_days")
        guard creditDays.map({ $0 <= Int64(Int.max) }) ?? true else {
            throw AppError.database(.rowReadFailed("party credit period is outside the supported range"))
        }
        return PartyProfile(
            accountId: try UUIDParsing.required(row.requiredText("account_id"), field: "avelo_party_profiles.account_id"),
            companyId: try UUIDParsing.required(row.requiredText("company_id"), field: "avelo_party_profiles.company_id"),
            usage: usage,
            creditLimitPaise: try row.checkedOptionalInt("credit_limit_paise"),
            defaultCreditPeriodDays: creditDays.map(Int.init),
            maintainBillwise: try row.requiredBool("maintain_billwise"),
            createdAt: try row.timestamp("created_at"),
            updatedAt: try row.timestamp("updated_at")
        )
    }
}
