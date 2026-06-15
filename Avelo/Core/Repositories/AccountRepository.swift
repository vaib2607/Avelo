import Foundation

public struct AccountRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: Account.ID) throws -> Account? {
        try db.queryOne(
            """
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
            FROM avelo_accounts
            WHERE id = ?
            """,
            bind: [.text(id.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func findByCode(_ code: String, companyId: Company.ID) throws -> Account? {
        try db.queryOne(
            """
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
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
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
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
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
            FROM avelo_accounts
            WHERE company_id = ?
            ORDER BY code COLLATE NOCASE
            """,
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToAccount($0) }
    }

    public func listLedgersForGroup(_ groupId: AccountGroup.ID) throws -> [Account] {
        try db.query(
            """
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
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
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
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
            SELECT id, company_id, group_id, code, name, opening_balance_paise, opening_balance_side,
                   is_active, is_bank_account, gstin, last_used_at, created_at, updated_at
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
             is_active, is_bank_account, gstin, last_used_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                is_active = ?, is_bank_account = ?, gstin = ?, last_used_at = ?, updated_at = ?
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
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_accounts.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_accounts.company_id")
        let groupId = try UUIDParsing.required(r.text("group_id"), field: "avelo_accounts.group_id")
        let sideRaw = r.text("opening_balance_side")
        let side = OpeningBalanceSide(rawValue: sideRaw) ?? .debit
        return Account(
            id: id,
            companyId: companyId,
            groupId: groupId,
            code: r.text("code"),
            name: r.text("name"),
            openingBalancePaise: r.int("opening_balance_paise"),
            openingBalanceSide: side,
            isActive: r.bool("is_active"),
            isBankAccount: r.bool("is_bank_account"),
            gstin: r.optionalText("gstin"),
            lastUsedAt: r.optionalText("last_used_at").flatMap { DateFormatters.parseTimestamp($0) },
            createdAt: try r.timestamp("created_at"),
            updatedAt: try r.timestamp("updated_at")
        )
    }
}
