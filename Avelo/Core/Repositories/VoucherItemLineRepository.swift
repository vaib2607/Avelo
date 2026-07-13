import Foundation

public struct VoucherItemLineRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private static let columns = "id, company_id, voucher_id, item_id, quantity, rate_paise, taxable_value_paise, hsn_code, gst_rate_bps, cgst_paise, sgst_paise, igst_paise, cess_paise, line_order, created_at"

    public func findForVoucher(_ voucherId: Voucher.ID) throws -> [VoucherItemLine] {
        try db.query(
            "SELECT \(Self.columns) FROM avelo_voucher_item_lines WHERE voucher_id = ? ORDER BY line_order ASC",
            bind: [.text(voucherId.uuidString)]
        ) { try Self.rowToLine($0) }
    }

    public func insertBatch(_ lines: [VoucherItemLine]) throws {
        for line in lines {
            try db.execute(
                """
                INSERT INTO avelo_voucher_item_lines
                (id, company_id, voucher_id, item_id, quantity, rate_paise, taxable_value_paise, hsn_code, gst_rate_bps, cgst_paise, sgst_paise, igst_paise, cess_paise, line_order, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(line.id.uuidString),
                    .text(line.companyId.uuidString),
                    .text(line.voucherId.uuidString),
                    .text(line.itemId.uuidString),
                    .integer(line.quantity),
                    .integer(line.ratePaise),
                    .integer(line.taxableValuePaise),
                    .optionalText(line.hsnCode),
                    .optionalInteger(line.gstRateBps.map(Int64.init)),
                    .integer(line.cgstPaise),
                    .integer(line.sgstPaise),
                    .integer(line.igstPaise),
                    .integer(line.cessPaise),
                    .integer(Int64(line.lineOrder)),
                    .timestamp(line.createdAt)
                ]
            )
        }
    }

    public func deleteForVoucher(_ voucherId: Voucher.ID) throws {
        try db.execute(
            "DELETE FROM avelo_voucher_item_lines WHERE voucher_id = ?",
            [.text(voucherId.uuidString)]
        )
    }

    static func rowToLine(_ r: Row) throws -> VoucherItemLine {
        let id = try UUIDParsing.required(r.requiredText("id"), field: "avelo_voucher_item_lines.id")
        let companyId = try UUIDParsing.required(r.requiredText("company_id"), field: "avelo_voucher_item_lines.company_id")
        let voucherId = try UUIDParsing.required(r.requiredText("voucher_id"), field: "avelo_voucher_item_lines.voucher_id")
        let itemId = try UUIDParsing.required(r.requiredText("item_id"), field: "avelo_voucher_item_lines.item_id")
        return VoucherItemLine(
            id: id,
            companyId: companyId,
            voucherId: voucherId,
            itemId: itemId,
            quantity: try r.requiredInt("quantity"),
            ratePaise: try r.requiredInt("rate_paise"),
            taxableValuePaise: try r.requiredInt("taxable_value_paise"),
            hsnCode: try r.checkedOptionalText("hsn_code"),
            gstRateBps: r.optionalInt("gst_rate_bps").map(Int.init),
            cgstPaise: try r.requiredInt("cgst_paise"),
            sgstPaise: try r.requiredInt("sgst_paise"),
            igstPaise: try r.requiredInt("igst_paise"),
            cessPaise: try r.requiredInt("cess_paise"),
            lineOrder: Int(try r.requiredInt("line_order")),
            createdAt: try r.timestamp("created_at")
        )
    }
}
