import Foundation

public struct VoucherRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findById(_ id: Voucher.ID) throws -> Voucher? {
        try db.queryOne(Self.selectAllSQL + " WHERE v.id = ?", bind: [.text(id.uuidString)]) {
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
        public var includeCancelled: Bool
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
                    includeCancelled: Bool = true,
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
            self.includeCancelled = includeCancelled
            self.limit = limit
            self.offset = offset
        }
    }

    public func list(filter: Filter) throws -> [Voucher] {
        let built = Self.filterWhereClause(filter)
        var sql = Self.selectAllSQL + built.sql
        var bind = built.bind
        sql += " ORDER BY v.date DESC, v.number DESC LIMIT ? OFFSET ?"
        bind.append(.integer(Int64(filter.limit)))
        bind.append(.integer(Int64(filter.offset)))
        return try db.query(sql, bind: bind) { try Self.rowToVoucher($0) }
    }

    /// AVL-P2-012 (narration recall, Ctrl+R): distinct narrations from this
    /// company's own voucher history, most recent first. Scoped per company
    /// like every other read here — no cross-company recall leakage.
    public func recentNarrations(companyId: Company.ID, limit: Int = 20) throws -> [String] {
        try db.query(
            """
            SELECT narration, MAX(date) AS last_used
            FROM avelo_vouchers
            WHERE company_id = ? AND length(trim(narration)) > 0
            GROUP BY narration
            ORDER BY last_used DESC
            LIMIT ?
            """,
            bind: [.text(companyId.uuidString), .integer(Int64(limit))]
        ) { try $0.requiredText("narration") }
    }

    public func count(filter: Filter) throws -> Int {
        let built = Self.filterWhereClause(filter)
        let sql = """
            SELECT COUNT(*)
            FROM avelo_vouchers v
            LEFT JOIN avelo_accounts a ON a.id = v.party_account_id
            \(built.sql)
            """
        return Int(try db.queryOne(sql, bind: built.bind) { $0.int(0) } ?? 0)
    }

    private static func filterWhereClause(_ filter: Filter) -> (sql: String, bind: [SQLValue]) {
        var sql = " WHERE v.company_id = ?"
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let fy = filter.financialYearId {
            sql += " AND v.financial_year_id = ?"
            bind.append(.text(fy.uuidString))
        }
        if let from = filter.fromDate {
            sql += " AND v.date >= ?"
            bind.append(.date(from))
        }
        if let to = filter.toDate {
            sql += " AND v.date <= ?"
            bind.append(.date(to))
        }
        if let party = filter.partyAccountId {
            sql += " AND v.party_account_id = ?"
            bind.append(.text(party.uuidString))
        }
        if !filter.voucherTypeCodes.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.voucherTypeCodes.count).joined(separator: ",")
            sql += " AND v.voucher_type_code IN (\(placeholders))"
            for code in filter.voucherTypeCodes {
                bind.append(.text(code.rawValue))
            }
        }
        if let n = filter.narrationContains, !n.isEmpty {
            sql += " AND v.narration LIKE ?"
            bind.append(.text("%\(n)%"))
        }
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            sql += " AND (v.number LIKE ? OR v.narration LIKE ? OR a.name LIKE ? OR a.code LIKE ?)"
            let term = "%\(search)%"
            bind.append(.text(term))
            bind.append(.text(term))
            bind.append(.text(term))
            bind.append(.text(term))
        }
        if filter.onlyReversed {
            sql += " AND v.is_reversal = 1"
        }
        if filter.onlyUnreversed {
            sql += " AND v.is_reversal = 0"
        }
        if !filter.includeCancelled {
            sql += " AND v.status != 'cancelled'"
        }
        return (sql, bind)
    }

    public func insert(_ voucher: Voucher) throws {
        try db.execute(
            """
            INSERT INTO avelo_vouchers
            (id, company_id, financial_year_id, voucher_type_code, number, date, party_account_id,
             narration, status, is_reversal, reversal_of_id, cancelled_at, cancelled_by, cancellation_reason,
             cancellation_voucher_id, is_posted, total_paise, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                .text(voucher.status.rawValue),
                .bool(voucher.isReversal),
                .optionalText(voucher.reversalOfId?.uuidString),
                .optionalTimestamp(voucher.cancelledAt),
                .optionalText(voucher.cancelledBy),
                .optionalText(voucher.cancellationReason),
                .optionalText(voucher.cancellationVoucherId?.uuidString),
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
            UPDATE avelo_vouchers SET
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

    public func markCancelled(_ voucher: Voucher) throws {
        try db.execute(
            """
            UPDATE avelo_vouchers SET
                status = ?, cancelled_at = ?, cancelled_by = ?, cancellation_reason = ?,
                cancellation_voucher_id = ?, updated_at = ?
            WHERE id = ?
            """,
            [
                .text(voucher.status.rawValue),
                .optionalTimestamp(voucher.cancelledAt),
                .optionalText(voucher.cancelledBy),
                .optionalText(voucher.cancellationReason),
                .optionalText(voucher.cancellationVoucherId?.uuidString),
                .timestamp(voucher.updatedAt),
                .text(voucher.id.uuidString)
            ]
        )
    }

    public func markReversal(originalId: Voucher.ID, reversalId: Voucher.ID) throws {
        try db.execute(
            "UPDATE avelo_vouchers SET reversal_of_id = ? WHERE id = ?",
            [.text(reversalId.uuidString), .text(originalId.uuidString)]
        )
    }

    public func hasReversal(for originalId: Voucher.ID) throws -> Bool {
        let exists: Int64? = try db.queryOne(
            "SELECT 1 FROM avelo_vouchers WHERE reversal_of_id = ? AND is_reversal = 1 LIMIT 1",
            bind: [.text(originalId.uuidString)]
        ) { $0.int(0) }
        return exists != nil
    }

    static let selectAllSQL: String = """
        SELECT v.id, v.company_id, v.financial_year_id, v.voucher_type_code, v.number, v.date, v.party_account_id,
               v.narration, v.status, v.is_reversal, v.reversal_of_id, v.cancelled_at, v.cancelled_by,
               v.cancellation_reason, v.cancellation_voucher_id, v.is_posted, v.total_paise, v.created_at, v.updated_at
        FROM avelo_vouchers v
        LEFT JOIN avelo_accounts a ON a.id = v.party_account_id
    """

    static func rowToVoucher(_ r: Row) throws -> Voucher {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_vouchers.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_vouchers.company_id")
        let fyId = try UUIDParsing.required(r.requiredText("financial_year_id"), field: "avelo_vouchers.financial_year_id")
        let code: VoucherType.Code = try r.enumValue("voucher_type_code")
        let party = try UUIDParsing.optional(try r.checkedOptionalText("party_account_id"), field: "avelo_vouchers.party_account_id")
        let reversalOf = try UUIDParsing.optional(try r.checkedOptionalText("reversal_of_id"), field: "avelo_vouchers.reversal_of_id")
        let cancellationVoucherId = try UUIDParsing.optional(try r.checkedOptionalText("cancellation_voucher_id"), field: "avelo_vouchers.cancellation_voucher_id")
        return Voucher(
            id: id,
            companyId: companyId,
            financialYearId: fyId,
            voucherTypeCode: code,
            number: try r.requiredText("number"),
            date: try r.requiredDate("date"),
            partyAccountId: party,
            narration: try r.requiredText("narration"),
            status: try r.enumValue("status"),
            isReversal: try r.requiredBool("is_reversal"),
            reversalOfId: reversalOf,
            cancelledAt: try r.optionalTimestamp("cancelled_at"),
            cancelledBy: try r.checkedOptionalText("cancelled_by"),
            cancellationReason: try r.checkedOptionalText("cancellation_reason"),
            cancellationVoucherId: cancellationVoucherId,
            isPosted: try r.requiredBool("is_posted"),
            totalPaise: try r.requiredInt("total_paise"),
            createdAt: try r.timestamp("created_at"),
            updatedAt: try r.timestamp("updated_at")
        )
    }
}
