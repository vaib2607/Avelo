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
}
