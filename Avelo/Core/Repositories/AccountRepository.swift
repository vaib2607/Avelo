import Foundation

public struct AccountRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    /// Single source of truth for the account SELECT column list.
    static let selectColumns = """
        id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
        is_active, is_bank_account, gstin, mailing_name, mailing_address, state_code, country,
        gst_registration_type, maintain_billwise, credit_period_days, last_used_at, created_at, updated_at
        """

    public struct Filter: Sendable {
        public var companyId: Company.ID
        public var groupId: AccountGroup.ID?
        public var searchText: String?
        public var includeInactive: Bool
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    groupId: AccountGroup.ID? = nil,
                    searchText: String? = nil,
                    includeInactive: Bool = true,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.groupId = groupId
            self.searchText = searchText
            self.includeInactive = includeInactive
            self.limit = limit
            self.offset = offset
        }
    }

    public func findById(_ id: Account.ID) throws -> Account? {
        try db.queryOne(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE id = ?
            """,
            bind: [.text(id.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func findByCode(_ code: String, companyId: Company.ID) throws -> Account? {
        try db.queryOne(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE company_id = ? AND code = ?
            """,
            bind: [.text(companyId.uuidString), .text(code)]
        ) { try Self.rowToAccount($0) }
    }

    public func findByCodes(_ codes: [String], companyId: Company.ID) throws -> [String: Account] {
        guard !codes.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: codes.count).joined(separator: ",")
        let sql = """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE company_id = ? AND code IN (\(placeholders))
            """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        for code in codes {
            bind.append(.text(code))
        }
        var out: [String: Account] = [:]
        _ = try db.query(sql, bind: bind) { row in
            let account = try Self.rowToAccount(row)
            out[account.code] = account
        }
        return out
    }

    public func listForCompany(_ companyId: Company.ID) throws -> [Account] {
        try db.query(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE company_id = ?
            ORDER BY code COLLATE NOCASE
            """,
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func listForCompany(_ companyId: Company.ID, limit: Int, offset: Int = 0) throws -> [Account] {
        try list(filter: .init(companyId: companyId, limit: limit, offset: offset))
    }

    public func list(filter: Filter) throws -> [Account] {
        let built = Self.filterWhereClause(filter)
        return try db.query(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            \(built.sql)
            ORDER BY code COLLATE NOCASE
            LIMIT ? OFFSET ?
            """,
            bind: built.bind + [.integer(Int64(filter.limit)), .integer(Int64(filter.offset))]
        ) { try Self.rowToAccount($0) }
    }

    public func count(filter: Filter) throws -> Int {
        let built = Self.filterWhereClause(filter)
        let sql = "SELECT COUNT(*) FROM avelo_accounts \(built.sql)"
        return Int(try db.queryOne(sql, bind: built.bind) { $0.int(0) } ?? 0)
    }

    private static func filterWhereClause(_ filter: Filter) -> (sql: String, bind: [SQLValue]) {
        var sql = "WHERE company_id = ?"
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let groupId = filter.groupId {
            sql += " AND group_id = ?"
            bind.append(.text(groupId.uuidString))
        }
        if !filter.includeInactive {
            sql += " AND is_active = 1"
        }
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            sql += " AND (name LIKE ? OR code LIKE ?)"
            let term = "%\(search)%"
            bind.append(.text(term))
            bind.append(.text(term))
        }
        return (sql, bind)
    }

    public func listLedgersForGroup(_ groupId: AccountGroup.ID) throws -> [Account] {
        try db.query(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE group_id = ? AND is_active = 1
            ORDER BY code COLLATE NOCASE
            """,
            bind: [.text(groupId.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func listActiveForCompany(_ companyId: Company.ID) throws -> [Account] {
        try db.query(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE company_id = ? AND is_active = 1
            ORDER BY code COLLATE NOCASE
            """,
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func listBankAccountsForCompany(_ companyId: Company.ID) throws -> [Account] {
        try db.query(
            """
            SELECT \(Self.selectColumns)
            FROM avelo_accounts
            WHERE company_id = ? AND is_bank_account = 1 AND is_active = 1
            ORDER BY code COLLATE NOCASE
            """,
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func insert(_ account: Account) throws {
        try db.execute(
            """
            INSERT INTO avelo_accounts
            (id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
             is_active, is_bank_account, gstin, mailing_name, mailing_address, state_code, country,
             gst_registration_type, maintain_billwise, credit_period_days, last_used_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(account.id.uuidString),
                .text(account.companyId.uuidString),
                .text(account.groupId.uuidString),
                .text(account.code),
                .text(account.name),
                .integer(account.openingBalancePaise),
                .text(account.openingBalanceSide.rawValue),
                .bool(account.isActive),
                .bool(account.isBankAccount),
                .optionalText(account.gstin),
                .optionalText(account.mailingName),
                .optionalText(account.mailingAddress),
                .optionalText(account.stateCode),
                .optionalText(account.country),
                .optionalText(account.gstRegistrationType?.rawValue),
                .bool(account.maintainBillwise ?? false),
                .optionalInteger(account.creditPeriodDays.map(Int64.init)),
                .optionalTimestamp(account.lastUsedAt),
                .timestamp(account.createdAt),
                .timestamp(account.updatedAt)
            ]
        )
    }

    public func update(_ account: Account) throws {
        try db.execute(
            """
            UPDATE avelo_accounts SET
                group_id = ?, code = ?, name = ?, opening_balance_paise = ?, opening_balance_side = ?,
                is_active = ?, is_bank_account = ?, gstin = ?, mailing_name = ?, mailing_address = ?,
                state_code = ?, country = ?, gst_registration_type = ?, maintain_billwise = ?,
                credit_period_days = ?, last_used_at = ?, updated_at = ?
            WHERE id = ?
            """,
            [
                .text(account.groupId.uuidString),
                .text(account.code),
                .text(account.name),
                .integer(account.openingBalancePaise),
                .text(account.openingBalanceSide.rawValue),
                .bool(account.isActive),
                .bool(account.isBankAccount),
                .optionalText(account.gstin),
                .optionalText(account.mailingName),
                .optionalText(account.mailingAddress),
                .optionalText(account.stateCode),
                .optionalText(account.country),
                .optionalText(account.gstRegistrationType?.rawValue),
                .bool(account.maintainBillwise ?? false),
                .optionalInteger(account.creditPeriodDays.map(Int64.init)),
                .optionalTimestamp(account.lastUsedAt),
                .timestamp(Date()),
                .text(account.id.uuidString)
            ]
        )
    }

    public func disable(_ id: Account.ID) throws {
        try db.execute(
            "UPDATE avelo_accounts SET is_active = 0, updated_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
    }

    public func markUsed(_ id: Account.ID) throws {
        try db.execute(
            "UPDATE avelo_accounts SET last_used_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
        if db.changes() == 0 {
            throw AppError.notFound("Account not found for usage update")
        }
    }

    public func markUsedBatch(_ ids: Set<Account.ID>) throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var bind: [SQLValue] = [.timestamp(Date())]
        for id in ids {
            bind.append(.text(id.uuidString))
        }
        try db.execute(
            "UPDATE avelo_accounts SET last_used_at = ? WHERE id IN (\(placeholders))",
            bind
        )
        if db.changes() == 0 {
            throw AppError.notFound("Accounts not found for usage update")
        }
    }

    static func rowToAccount(_ r: Row) throws -> Account {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_accounts.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_accounts.company_id")
        let groupId = try UUIDParsing.required(r.requiredText("group_id"), field: "avelo_accounts.group_id")
        let side: OpeningBalanceSide = try r.enumValue("opening_balance_side")
        return Account(
            id: id,
            companyId: companyId,
            groupId: groupId,
            code: try r.requiredText("code"),
            name: try r.requiredText("name"),
            openingBalancePaise: try r.requiredInt("opening_balance_paise"),
            openingBalanceSide: side,
            isActive: try r.requiredBool("is_active"),
            isBankAccount: try r.requiredBool("is_bank_account"),
            gstin: try r.checkedOptionalText("gstin"),
            mailingName: try r.checkedOptionalText("mailing_name"),
            mailingAddress: try r.checkedOptionalText("mailing_address"),
            stateCode: try r.checkedOptionalText("state_code"),
            country: try r.checkedOptionalText("country"),
            gstRegistrationType: (try r.checkedOptionalText("gst_registration_type")).flatMap(GSTRegistrationType.init(rawValue:)),
            maintainBillwise: try r.requiredBool("maintain_billwise"),
            creditPeriodDays: r.optionalInt("credit_period_days").map(Int.init),
            lastUsedAt: try r.optionalTimestamp("last_used_at"),
            createdAt: try r.timestamp("created_at"),
            updatedAt: try r.timestamp("updated_at")
        )
    }
}
