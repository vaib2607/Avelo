import Foundation

public struct VoucherNumberGenerator: Sendable {

    public let db: SQLiteDatabase
    private static let fyShortCacheLock = NSLock()
    private static var fyShortCache: [String: String] = [:]

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func next(companyId: Company.ID,
                     financialYearId: FinancialYear.ID,
                     typeCode: VoucherType.Code) throws -> String {
        try nextBatch(companyId: companyId, financialYearId: financialYearId, typeCode: typeCode, count: 1)[0]
    }

    public func nextBatch(companyId: Company.ID,
                          financialYearId: FinancialYear.ID,
                          typeCode: VoucherType.Code,
                          count: Int) throws -> [String] {
        guard count > 0 else { return [] }
        let prefix: String
        let padding: Int
        let fyShort = try Self.shortFY(of: financialYearId, db: db)

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
            let firstN = row.2 + 1
            let lastN = row.2 + count
            try db.execute(
                "UPDATE avelo_voucher_sequences SET last_number = ? WHERE company_id = ? AND financial_year_id = ? AND voucher_type_code = ?",
                [
                    .integer(Int64(lastN)),
                    .text(companyId.uuidString),
                    .text(financialYearId.uuidString),
                    .text(typeCode.rawValue)
                ]
            )
<<<<<<< HEAD:Avelo/Core/Utilities/VoucherNumberGenerator.swift
            return (firstN...lastN).map { formatNumber(prefix: prefix, fyShort: fyShort, n: $0, padding: padding) }
=======
            return formatNumber(prefix: prefix, fyShort: fyShort, n: nextN, padding: padding)
>>>>>>> origin/main:Mally/Core/Utilities/VoucherNumberGenerator.swift
        } else {
            prefix = typeCode.defaultPrefix
            padding = typeCode.defaultPadding
            try db.execute(
<<<<<<< HEAD:Avelo/Core/Utilities/VoucherNumberGenerator.swift
                "INSERT INTO avelo_voucher_sequences (company_id, financial_year_id, voucher_type_code, last_number, prefix, suffix, padding) VALUES (?, ?, ?, ?, ?, NULL, ?)",
=======
                "INSERT INTO avelo_voucher_sequences (company_id, financial_year_id, voucher_type_code, last_number, prefix, suffix, padding) VALUES (?, ?, ?, 1, ?, NULL, ?)",
>>>>>>> origin/main:Mally/Core/Utilities/VoucherNumberGenerator.swift
                [
                    .text(companyId.uuidString),
                    .text(financialYearId.uuidString),
                    .text(typeCode.rawValue),
                    .integer(Int64(count)),
                    .text(prefix),
                    .integer(Int64(padding))
                ]
            )
<<<<<<< HEAD:Avelo/Core/Utilities/VoucherNumberGenerator.swift
            return (1...count).map { formatNumber(prefix: prefix, fyShort: fyShort, n: $0, padding: padding) }
=======
            return formatNumber(prefix: prefix, fyShort: fyShort, n: 1, padding: padding)
>>>>>>> origin/main:Mally/Core/Utilities/VoucherNumberGenerator.swift
        }
    }

    private static func shortFY(of fyId: FinancialYear.ID, db: SQLiteDatabase) throws -> String {
        let key = fyId.uuidString
        Self.fyShortCacheLock.lock()
        if let cached = fyShortCache[key] {
            Self.fyShortCacheLock.unlock()
            return cached
        }
        Self.fyShortCacheLock.unlock()
        let label: String? = try db.queryOne(
            "SELECT label FROM avelo_financial_years WHERE id = ?",
            bind: [.text(fyId.uuidString)]
        ) { r in r.text("label") }
        guard let label else { return "0000" }
        let short: String
        if let y = IndianFinancialYear.startYear(fromLabel: label) {
            short = String(format: "%02d-%02d", y % 100, (y + 1) % 100)
        } else {
            short = label
        }
        Self.fyShortCacheLock.lock()
        fyShortCache[key] = short
        Self.fyShortCacheLock.unlock()
        return short
    }

    private func formatNumber(prefix: String, fyShort: String, n: Int, padding: Int) -> String {
        let nStr = String(format: "%0\(padding)d", n)
        return "\(prefix)/\(fyShort)/\(nStr)"
    }
}
