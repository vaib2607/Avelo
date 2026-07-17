import Foundation

public final class VoucherTemplateService: Sendable {
    public let db: SQLiteDatabase
    public let repository: VoucherTemplateRepository
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = VoucherTemplateRepository(db: db)
        self.companyId = companyId
    }

    public func save(name: String, draft: VoucherDraft) throws {
        let encodedLines = try JSONEncoder().encode(draft.lines.map { line in
            TemplateLineDTO(accountId: line.accountId?.uuidString,
                           amountPaise: line.amountPaise,
                           side: line.side.rawValue,
                           taxCode: line.taxCode,
                           costCenter: line.costCenter,
                           lineOrder: line.lineOrder)
        })
        let template = VoucherTemplate(companyId: companyId,
                                       name: name,
                                       voucherTypeCode: draft.voucherTypeCode,
                                       templateLinesJSON: String(data: encodedLines, encoding: .utf8) ?? "[]")
        try db.write { tx in
            let repository = VoucherTemplateRepository(db: tx)
            let before = try repository.find(companyId: companyId, name: name)
            let saved = VoucherTemplate(
                id: before?.id ?? template.id,
                companyId: template.companyId,
                name: template.name,
                voucherTypeCode: template.voucherTypeCode,
                description: template.description,
                templateLinesJSON: template.templateLinesJSON,
                isActive: template.isActive,
                createdAt: before?.createdAt ?? template.createdAt
            )
            try repository.upsert(saved)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherTemplateSaved,
                entityType: "voucher_template",
                entityId: saved.id.uuidString,
                snapshotBefore: before,
                snapshotAfter: saved
            )
        }
    }

    public func load(name: String) throws -> VoucherDraft? {
        guard let template = try repository.find(companyId: companyId, name: name) else { return nil }
        let decoded = try JSONDecoder().decode([TemplateLineDTO].self, from: Data(template.templateLinesJSON.utf8))
        return VoucherDraft(mode: .create,
                            voucherTypeCode: template.voucherTypeCode,
                            date: Date(),
                            lines: decoded.map {
                                VoucherDraft.Line(accountId: UUID(uuidString: $0.accountId ?? ""),
                                                  amountPaise: $0.amountPaise,
                                                  side: $0.side == "credit" ? .credit : .debit,
                                                  taxCode: $0.taxCode,
                                                  costCenter: $0.costCenter,
                                                  lineOrder: $0.lineOrder)
                            })
    }
}

private struct TemplateLineDTO: Codable {
    let accountId: String?
    let amountPaise: Int64
    let side: String
    let taxCode: String?
    let costCenter: String?
    let lineOrder: Int
}
