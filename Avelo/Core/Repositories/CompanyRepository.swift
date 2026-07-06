import Foundation

public struct CompanyRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: Company.ID) throws -> Company? {
        try db.queryOne(
            "SELECT id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at FROM avelo_companies WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToCompany($0) }
    }

    public func listForRegistry() throws -> [Company] {
        try db.query(
            "SELECT id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at FROM avelo_companies ORDER BY name COLLATE NOCASE"
        ) { try Self.rowToCompany($0) }
    }

    public func insert(_ company: Company) throws -> Company {
        try db.execute(
            "INSERT INTO avelo_companies (id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(company.id.uuidString),
                .text(company.name),
                .optionalText(company.addressLine1),
                .optionalText(company.addressLine2),
                .optionalText(company.city),
                .optionalText(company.state),
                .optionalText(company.pincode),
                .text(company.country),
                .optionalText(company.gstin),
                .optionalText(company.pan),
                .text(company.baseCurrency),
                .bool(company.isInventoryEnabled),
                .text(company.inventoryLinkMode.rawValue),
                .timestamp(company.createdAt),
                .timestamp(company.updatedAt)
            ]
        )
        return company
    }

    public func update(_ company: Company) throws {
        try db.execute(
            "UPDATE avelo_companies SET name = ?, address_line1 = ?, address_line2 = ?, city = ?, state = ?, pincode = ?, country = ?, gstin = ?, pan = ?, base_currency = ?, is_inventory_enabled = ?, inventory_link_mode = ?, updated_at = ? WHERE id = ?",
            [
                .text(company.name),
                .optionalText(company.addressLine1),
                .optionalText(company.addressLine2),
                .optionalText(company.city),
                .optionalText(company.state),
                .optionalText(company.pincode),
                .text(company.country),
                .optionalText(company.gstin),
                .optionalText(company.pan),
                .text(company.baseCurrency),
                .bool(company.isInventoryEnabled),
                .text(company.inventoryLinkMode.rawValue),
                .timestamp(Date()),
                .text(company.id.uuidString)
            ]
        )
    }

    public func disable(_ id: Company.ID) throws {
        try db.execute(
            "UPDATE avelo_companies SET updated_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
    }

    static func rowToCompany(_ r: Row) throws -> Company {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_companies.id")
        let mode: InventoryLinkMode = try r.enumValue("inventory_link_mode")
        return Company(
            id: id,
            name: try r.requiredText("name"),
            addressLine1: try r.checkedOptionalText("address_line1"),
            addressLine2: try r.checkedOptionalText("address_line2"),
            city: try r.checkedOptionalText("city"),
            state: try r.checkedOptionalText("state"),
            pincode: try r.checkedOptionalText("pincode"),
            country: try r.requiredText("country"),
            gstin: try r.checkedOptionalText("gstin"),
            pan: try r.checkedOptionalText("pan"),
            baseCurrency: try r.requiredText("base_currency"),
            isInventoryEnabled: try r.requiredBool("is_inventory_enabled"),
            inventoryLinkMode: mode,
            createdAt: try r.timestamp("created_at"),
            updatedAt: try r.timestamp("updated_at")
        )
    }
}
