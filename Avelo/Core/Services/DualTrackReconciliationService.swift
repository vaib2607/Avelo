import Foundation

/// Read-only integrity diagnostic for canonical dual-track vouchers. It
/// deliberately never repairs or substitutes balances.
public struct DualTrackReconciliationService: Sendable {
    public struct Finding: Hashable, Sendable, Identifiable {
        public let id: String
        public let voucherId: Voucher.ID?
        public let message: String
    }

    public let db: SQLiteDatabase
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.companyId = companyId
    }

    public func findings() throws -> [Finding] {
        var result: [Finding] = []
        // Financial report paths already run `verifyPostedVouchersBalance`
        // with the selected company/FY/as-of scope. Do not duplicate it here
        // globally: a malformed earlier FY must not block a later scoped
        // Balance Sheet.
        let evidenceWithoutMovement: [String] = try db.query(
            """
            SELECT il.id FROM avelo_voucher_item_lines il
            LEFT JOIN trn_inventory i ON i.item_line_id = il.id
            WHERE il.company_id = ? AND i.id IS NULL
            """, bind: [.text(companyId.uuidString)]
        ) { try $0.requiredText("id") }
        result += evidenceWithoutMovement.map { .init(id: "evidence-\($0)", voucherId: nil, message: "Item evidence has no canonical inventory movement.") }
        let movementWithoutEvidence: [String] = try db.query(
            """
            SELECT i.id FROM trn_inventory i
            LEFT JOIN avelo_voucher_item_lines il ON il.id = i.item_line_id
            WHERE i.company_id = ? AND i.voucher_id IS NOT NULL AND i.item_line_id IS NOT NULL AND il.id IS NULL
            """, bind: [.text(companyId.uuidString)]
        ) { try $0.requiredText("id") }
        result += movementWithoutEvidence.map { .init(id: "movement-\($0)", voucherId: nil, message: "Canonical inventory movement has invalid item evidence.") }
        return result
    }

    public func verify() throws {
        let problems = try findings()
        guard problems.isEmpty else {
            throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "dualTrack", message: problems[0].message))
        }
    }

    /// Balance Sheet coherence is deliberately narrower than the global
    /// diagnostic: historic inventory evidence must not block a selected FY.
    public func verify(balanceSheetScope scope: BalanceSheetScope) throws {
        guard scope.companyId == companyId else {
            throw AppError.validation(.init(code: .reportFinancialYearCompanyMismatch, field: "companyId", message: "Balance Sheet scope belongs to another company."))
        }
        let vouchers: [(String, String, Date, String?, Date?, Date?)] = try db.query(
            """
            SELECT v.id, v.company_id, v.date, fy.company_id AS fy_company_id,
                   fy.start_date AS fy_start_date, fy.end_date AS fy_end_date
            FROM avelo_vouchers v
            LEFT JOIN avelo_financial_years fy ON fy.id = v.financial_year_id
            WHERE v.company_id = ? AND v.financial_year_id = ?
            """, bind: [.text(scope.companyId.uuidString), .text(scope.financialYearId.uuidString)]
        ) { row in
            (try row.requiredText("id"), try row.requiredText("company_id"), try row.requiredDate("date"),
             try row.checkedOptionalText("fy_company_id"), try row.checkedOptionalDate("fy_start_date"), try row.checkedOptionalDate("fy_end_date"))
        }
        for (voucherId, voucherCompanyId, date, fyCompanyId, fyStart, fyEnd) in vouchers {
            guard voucherCompanyId == scope.companyId.uuidString,
                  fyCompanyId == scope.companyId.uuidString,
                  let fyStart, let fyEnd, date >= fyStart, date <= fyEnd else {
                throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "voucherId", message: "Voucher \(voucherId) has an invalid company, financial year, or date relationship."))
            }
        }
        let activityPredicate = "v.company_id = ? AND v.financial_year_id = ? AND v.date >= ? AND v.date <= ?"
        let bind: [SQLValue] = [.text(scope.companyId.uuidString), .text(scope.financialYearId.uuidString), .date(scope.financialYearStartDate), .date(scope.asOfDate)]
        let evidenceWithoutMovement: [String] = try db.query(
            """
            SELECT il.id FROM avelo_voucher_item_lines il
            JOIN avelo_vouchers v ON v.id = il.voucher_id
            LEFT JOIN trn_inventory i ON i.item_line_id = il.id
            WHERE \(activityPredicate) AND i.id IS NULL
            """, bind: bind
        ) { try $0.requiredText("id") }
        guard evidenceWithoutMovement.isEmpty else {
            throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "dualTrack", message: "Item evidence has no canonical inventory movement."))
        }
        let movementWithoutEvidence: [String] = try db.query(
            """
            SELECT i.id FROM trn_inventory i
            JOIN avelo_vouchers v ON v.id = i.voucher_id
            LEFT JOIN avelo_voucher_item_lines il ON il.id = i.item_line_id
            WHERE \(activityPredicate) AND i.item_line_id IS NOT NULL AND il.id IS NULL
            """, bind: bind
        ) { try $0.requiredText("id") }
        guard movementWithoutEvidence.isEmpty else {
            throw AppError.validation(.init(code: .canonicalTrackCoherenceFailure, field: "dualTrack", message: "Canonical inventory movement has invalid item evidence."))
        }
    }
}
