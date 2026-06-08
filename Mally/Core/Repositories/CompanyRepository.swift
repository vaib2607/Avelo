import Foundation

public struct CompanyRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: Company.ID) throws -> Company? {
        try db.queryOne(
            "SELECT id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at FROM mally_companies WHERE id = ?",
            bind: [.text(id.uuidString)]
        ) { try Self.rowToCompany($0) }
    }

    public func listForRegistry() throws -> [Company] {
        try db.query(
            "SELECT id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at FROM mally_companies ORDER BY name COLLATE NOCASE"
        ) { try Self.rowToCompany($0) }
    }

    public func insert(_ company: Company) throws -> Company {
        try db.execute(
            "INSERT INTO mally_companies (id, name, address_line1, address_line2, city, state, pincode, country, gstin, pan, base_currency, is_inventory_enabled, inventory_link_mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
            "UPDATE mally_companies SET name = ?, address_line1 = ?, address_line2 = ?, city = ?, state = ?, pincode = ?, country = ?, gstin = ?, pan = ?, base_currency = ?, is_inventory_enabled = ?, inventory_link_mode = ?, updated_at = ? WHERE id = ?",
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
            "UPDATE mally_companies SET updated_at = ? WHERE id = ?",
            [.timestamp(Date()), .text(id.uuidString)]
        )
    }

    static func rowToCompany(_ r: Row) throws -> Company {
        let id = try UUIDParsing.required(r.text("id"), field: "mally_companies.id")
        let modeRaw = r.text("inventory_link_mode")
        let mode = InventoryLinkMode(rawValue: modeRaw) ?? .manual
        return Company(
            id: id,
            name: r.text("name"),
            addressLine1: r.optionalText("address_line1"),
            addressLine2: r.optionalText("address_line2"),
            city: r.optionalText("city"),
            state: r.optionalText("state"),
            pincode: r.optionalText("pincode"),
            country: r.text("country"),
            gstin: r.optionalText("gstin"),
            pan: r.optionalText("pan"),
            baseCurrency: r.text("base_currency"),
            isInventoryEnabled: r.bool("is_inventory_enabled"),
            inventoryLinkMode: mode,
            createdAt: r.timestamp("created_at"),
            updatedAt: r.timestamp("updated_at")
        )
    }
}
