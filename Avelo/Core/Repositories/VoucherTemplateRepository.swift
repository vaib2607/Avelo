import Foundation

public struct VoucherTemplateRepository: Sendable {
    public let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func upsert(_ template: VoucherTemplate) throws {
        try db.execute(
            """
            INSERT INTO avelo_voucher_templates
            (id, company_id, name, voucher_type_code, description, template_lines_json, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(company_id, name) DO UPDATE SET
                voucher_type_code = excluded.voucher_type_code,
                description = excluded.description,
                template_lines_json = excluded.template_lines_json,
                is_active = excluded.is_active
            """,
            [
                .text(template.id.uuidString),
                .text(template.companyId.uuidString),
                .text(template.name),
                .text(template.voucherTypeCode.rawValue),
                .optionalText(template.description),
                .text(template.templateLinesJSON),
                .bool(template.isActive),
                .timestamp(template.createdAt)
            ]
        )
    }

    public func find(companyId: Company.ID, name: String) throws -> VoucherTemplate? {
        try db.queryOne(
            "SELECT id, company_id, name, voucher_type_code, description, template_lines_json, is_active, created_at FROM avelo_voucher_templates WHERE company_id = ? AND name = ?",
            bind: [.text(companyId.uuidString), .text(name)]
        ) { r in
            return VoucherTemplate(
                id: try UUIDParsing.required(r.requiredText("id"), field: "avelo_voucher_templates.id"),
                companyId: try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_voucher_templates.company_id"),
                name: try r.requiredText("name"),
                voucherTypeCode: try r.enumValue("voucher_type_code"),
                description: try r.checkedOptionalText("description"),
                templateLinesJSON: try r.requiredText("template_lines_json"),
                isActive: try r.requiredBool("is_active"),
                createdAt: try r.timestamp("created_at")
            )
        }
    }
}
