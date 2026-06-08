import Foundation

public struct VoucherNumberGenerator: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func next(companyId: Company.ID,
                     financialYearId: FinancialYear.ID,
                     typeCode: VoucherType.Code) throws -> String {
        let prefix: String
        let padding: Int
        let fyShort: String

        let row = try db.queryOne(
            "SELECT prefix, padding, last_number FROM avelo_voucher_sequences WHERE company_id = ? AND financial_year_id = ? AND voucher_type_code = ?",
            bind: [
                .text(companyId.uuidString),
                .text(financialYearId.uuidString),
                .text(typeCode.rawValue)
            ]
        ) { r -> (String, Int, Int) in
            (r.text("prefix"), Int(r.int("padding")), Int(r.int("last_number")))
        }

        if let row = row {
            prefix = row.0
            padding = row.1
            let nextN = row.2 + 1
            try db.execute(
                "UPDATE avelo_voucher_sequences SET last_number = ? WHERE company_id = ? AND financial_year_id = ? AND voucher_type_code = ?",
                [
                    .integer(Int64(nextN)),
                    .text(companyId.uuidString),
                    .text(financialYearId.uuidString),
                    .text(typeCode.rawValue)
                ]
            )
            fyShort = try shortFY(of: financialYearId)
            return formatNumber(prefix: prefix, fyShort: fyShort, n: nextN, padding: padding)
        } else {
            prefix = typeCode.defaultPrefix
            padding = typeCode.defaultPadding
            try db.execute(
                "INSERT INTO avelo_voucher_sequences (company_id, financial_year_id, voucher_type_code, last_number, prefix, suffix, padding) VALUES (?, ?, ?, 1, ?, NULL, ?)",
                [
                    .text(companyId.uuidString),
                    .text(financialYearId.uuidString),
                    .text(typeCode.rawValue),
                    .text(prefix),
                    .integer(Int64(padding))
                ]
            )
            fyShort = try shortFY(of: financialYearId)
            return formatNumber(prefix: prefix, fyShort: fyShort, n: 1, padding: padding)
        }
    }

    private func shortFY(of fyId: FinancialYear.ID) throws -> String {
        let label: String? = try db.queryOne(
            "SELECT label FROM avelo_financial_years WHERE id = ?",
            bind: [.text(fyId.uuidString)]
        ) { r in r.text("label") }
        guard let label else { return "0000" }
        if let y = IndianFinancialYear.startYear(fromLabel: label) {
            return String(format: "%02d-%02d", y % 100, (y + 1) % 100)
        }
        return label
    }

    private func formatNumber(prefix: String, fyShort: String, n: Int, padding: Int) -> String {
        let nStr = String(format: "%0\(padding)d", n)
        return "\(prefix)/\(fyShort)/\(nStr)"
    }
}
