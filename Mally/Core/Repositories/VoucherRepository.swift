import Foundation

public struct VoucherRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: Voucher.ID) throws -> Voucher? {
        try db.queryOne(Self.selectAllSQL + " WHERE id = ?", bind: [.text(id.uuidString)]) {
            try Self.rowToVoucher($0)
        }
    }

    public struct Filter: Sendable {
        public var companyId: Company.ID
        public var financialYearId: FinancialYear.ID?
        public var fromDate: Date?
        public var toDate: Date?
        public var partyAccountId: Account.ID?
        public var voucherTypeCodes: Set<VoucherType.Code>
        public var narrationContains: String?
        public var searchText: String?
        public var onlyReversed: Bool
        public var onlyUnreversed: Bool
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    financialYearId: FinancialYear.ID? = nil,
                    fromDate: Date? = nil,
                    toDate: Date? = nil,
                    partyAccountId: Account.ID? = nil,
                    voucherTypeCodes: Set<VoucherType.Code> = [],
                    narrationContains: String? = nil,
                    searchText: String? = nil,
                    onlyReversed: Bool = false,
                    onlyUnreversed: Bool = false,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.financialYearId = financialYearId
            self.fromDate = fromDate
            self.toDate = toDate
            self.partyAccountId = partyAccountId
            self.voucherTypeCodes = voucherTypeCodes
            self.narrationContains = narrationContains
            self.searchText = searchText
            self.onlyReversed = onlyReversed
            self.onlyUnreversed = onlyUnreversed
            self.limit = limit
            self.offset = offset
        }
    }

    public func list(filter: Filter) throws -> [Voucher] {
        var sql = Self.selectAllSQL + " WHERE company_id = ?"
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let fy = filter.financialYearId {
            sql += " AND financial_year_id = ?"
            bind.append(.text(fy.uuidString))
        }
        if let from = filter.fromDate {
            sql += " AND date >= ?"
            bind.append(.date(from))
        }
        if let to = filter.toDate {
            sql += " AND date <= ?"
            bind.append(.date(to))
        }
        if let party = filter.partyAccountId {
            sql += " AND party_account_id = ?"
            bind.append(.text(party.uuidString))
        }
        if !filter.voucherTypeCodes.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.voucherTypeCodes.count).joined(separator: ",")
            sql += " AND voucher_type_code IN (\(placeholders))"
            for code in filter.voucherTypeCodes {
                bind.append(.text(code.rawValue))
            }
        }
        if let n = filter.narrationContains, !n.isEmpty {
            sql += " AND narration LIKE ?"
            bind.append(.text("%\(n)%"))
        }
        if filter.onlyReversed {
            sql += " AND is_reversal = 1"
        }
        if filter.onlyUnreversed {
            sql += " AND is_reversal = 0"
        }
        sql += " ORDER BY date DESC, number DESC LIMIT ? OFFSET ?"
        bind.append(.integer(Int64(filter.limit)))
        bind.append(.integer(Int64(filter.offset)))
        return try db.query(sql, bind: bind) { try Self.rowToVoucher($0) }
    }

    public func insert(_ voucher: Voucher) throws {
        try db.execute(
            """
            INSERT INTO mally_vouchers
            (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
             narration, reference, is_reversal, reversal_of_id, is_posted, total_paise, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(voucher.id.uuidString),
                .text(voucher.companyId.uuidString),
                .text(voucher.financialYearId.uuidString),
                .text(voucher.voucherTypeCode.rawValue),
                .text(voucher.number),
                .date(voucher.date),
                .optionalText(voucher.partyAccountId?.uuidString),
                .text(voucher.narration),
                .text(voucher.reference),
                .bool(voucher.isReversal),
                .optionalText(voucher.reversalOfId?.uuidString),
                .bool(voucher.isPosted),
                .integer(voucher.totalPaise),
                .timestamp(voucher.createdAt),
                .timestamp(voucher.updatedAt)
            ]
        )
    }

    public func update(_ voucher: Voucher) throws {
        try db.execute(
            """
            UPDATE mally_vouchers SET
                date = ?, party_account_id = ?, narration = ?, total_paise = ?, updated_at = ?
            WHERE id = ?
            """,
            [
                .date(voucher.date),
                .optionalText(voucher.partyAccountId?.uuidString),
                .text(voucher.narration),
                .integer(voucher.totalPaise),
                .timestamp(Date()),
                .text(voucher.id.uuidString)
            ]
        )
    }

    public func markReversal(originalId: Voucher.ID, reversalId: Voucher.ID) throws {
        try db.execute(
            "UPDATE mally_vouchers SET reversal_of_id = ? WHERE id = ?",
            [.text(reversalId.uuidString), .text(originalId.uuidString)]
        )
    }

    static let selectAllSQL: String = """
        SELECT id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
               narration, reference, is_reversal, reversal_of_id, is_posted, total_paise, created_at, updated_at
        FROM mally_vouchers
    """

    static func rowToVoucher(_ r: Row) throws -> Voucher {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let fyId = UUID(uuidString: r.text("financial_year_id")) ?? UUID()
        let codeRaw = r.text("voucher_type_code")
        let code = VoucherType.Code(rawValue: codeRaw) ?? .journal
        let party = r.optionalText("party_account_id").flatMap { UUID(uuidString: $0) }
        let reversalOf = r.optionalText("reversal_of_id").flatMap { UUID(uuidString: $0) }
        return Voucher(
            id: id,
            companyId: companyId,
            financialYearId: fyId,
            voucherTypeCode: code,
            number: r.text("number"),
            date: r.date("date"),
            partyAccountId: party,
            narration: r.text("narration"),
            isReversal: r.bool("is_reversal"),
            reversalOfId: reversalOf,
            isPosted: r.bool("is_posted"),
            totalPaise: r.int("total_paise"),
            reference: r.optionalText("reference") ?? "",
            createdAt: r.timestamp("created_at"),
            updatedAt: r.timestamp("updated_at")
        )
    }
}
