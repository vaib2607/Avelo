import Foundation

public struct AccountGroupRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: AccountGroup.ID) throws -> AccountGroup? {
        try db.queryOne(
            "SELECT id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at FROM avelo_account_groups WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToGroup($0) }
    }

    public func listForCompany(_ companyId: Company.ID) throws -> [AccountGroup] {
        try db.query(
            "SELECT id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at FROM avelo_account_groups WHERE company_id = ? ORDER BY sort_order, code",
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToGroup($0) }
    }

    public func listRootsForCompany(_ companyId: Company.ID) throws -> [AccountGroup] {
        try db.query(
            "SELECT id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at FROM avelo_account_groups WHERE company_id = ? AND parent_group_id IS NULL ORDER BY sort_order, code",
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToGroup($0) }
    }

    public func listChildren(of parentId: AccountGroup.ID) throws -> [AccountGroup] {
        try db.query(
            "SELECT id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at FROM avelo_account_groups WHERE parent_group_id = ? ORDER BY sort_order, code",
            bind: [.text(parentId.uuidString)]
        ) { try Self.rowToGroup($0) }
    }

    public func listLeafGroupsForCompany(_ companyId: Company.ID) throws -> [AccountGroup] {
        try db.query(
            """
            SELECT g.id, g.company_id, g.parent_group_id, g.code, g.name, g.nature, g.is_active, g.sort_order, g.created_at
            FROM avelo_account_groups g
            WHERE g.company_id = ?
              AND g.is_active = 1
              AND NOT EXISTS (SELECT 1 FROM avelo_account_groups c WHERE c.parent_group_id = g.id)
            ORDER BY g.sort_order, g.code
            """,
            bind: [.text(companyId.uuidString)]
        ) { try Self.rowToGroup($0) }
    }

    public func insert(_ group: AccountGroup) throws {
        try db.execute(
            "INSERT INTO avelo_account_groups (id, company_id, parent_group_id, code, name, nature, is_active, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(group.id.uuidString),
                .text(group.companyId.uuidString),
                .optionalText(group.parentGroupId?.uuidString),
                .text(group.code),
                .text(group.name),
                .text(group.nature.rawValue),
                .bool(group.isActive),
                .integer(Int64(group.sortOrder)),
                .timestamp(group.createdAt)
            ]
        )
    }

    public func update(_ group: AccountGroup) throws {
        try db.execute(
            "UPDATE avelo_account_groups SET parent_group_id = ?, name = ?, nature = ?, is_active = ?, sort_order = ? WHERE id = ?",
            [
                .optionalText(group.parentGroupId?.uuidString),
                .text(group.name),
                .text(group.nature.rawValue),
                .bool(group.isActive),
                .integer(Int64(group.sortOrder)),
                .text(group.id.uuidString)
            ]
        )
    }

    public func delete(_ id: AccountGroup.ID) throws {
        try db.execute(
            "DELETE FROM avelo_account_groups WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    static func rowToGroup(_ r: Row) throws -> AccountGroup {
<<<<<<< HEAD:Avelo/Core/Repositories/AccountGroupRepository.swift
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_account_groups.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_account_groups.company_id")
        let parentId = try UUIDParsing.optional(try r.checkedOptionalText("parent_group_id"), field: "avelo_account_groups.parent_group_id")
        let nature: AccountNature = try r.enumValue("nature")
=======
        let id = try UUIDParsing.required(r.text("id"), field: "avelo_account_groups.id")
        let companyId = try UUIDParsing.required(r.text("company_id"), field: "avelo_account_groups.company_id")
        let parentId = try UUIDParsing.optional(r.optionalText("parent_group_id"), field: "avelo_account_groups.parent_group_id")
        let natureRaw = r.text("nature")
        let nature = AccountNature(rawValue: natureRaw) ?? .assets
>>>>>>> origin/main:Mally/Core/Repositories/AccountGroupRepository.swift
        return AccountGroup(
            id: id,
            companyId: companyId,
            parentGroupId: parentId,
            code: try r.requiredText("code"),
            name: try r.requiredText("name"),
            nature: nature,
            isActive: try r.requiredBool("is_active"),
            sortOrder: Int(try r.requiredInt("sort_order")),
            createdAt: try r.timestamp("created_at")
        )
    }
}
