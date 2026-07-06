import Foundation

extension ReportRepository {
    // MARK: - GST Summary

    public func gstSummary(fromDate: Date, toDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.GstSummary {
        struct Bucket { let accountCode: String; let sign: Int }
        let codes: [Bucket] = [
            .init(accountCode: "CGST_OUTPUT", sign: 1),
            .init(accountCode: "SGST_OUTPUT", sign: 1),
            .init(accountCode: "IGST_OUTPUT", sign: 1),
            .init(accountCode: "CESS",        sign: 1),
            .init(accountCode: "CGST_INPUT",  sign: -1),
            .init(accountCode: "SGST_INPUT",  sign: -1),
            .init(accountCode: "IGST_INPUT",  sign: -1)
        ]
        let accountsByCode = try AccountRepository(db: db).findByCodes(codes.map(\.accountCode), companyId: filter.companyId)
        let totalsByAccount = try movementTotals(
            for: Array(accountsByCode.values.map(\.id)),
            companyId: filter.companyId,
            fromDate: fromDate,
            toDate: toDate
        )
        var output: [ReportResult.GstBucket] = []
        var input: [ReportResult.GstBucket] = []
        var net: Int64 = 0
        for c in codes {
            let acct = accountsByCode[c.accountCode]
            guard let acct else { continue }
            let totals = totalsByAccount[acct.id]
            let dr = totals?.debitPaise ?? 0
            let cr = totals?.creditPaise ?? 0
            let netAmt = c.sign > 0
                ? try CheckedMath.subtract(cr, dr, context: "calculating GST bucket output net")
                : try CheckedMath.subtract(dr, cr, context: "calculating GST bucket input net")
            let label = "\(c.accountCode.replacingOccurrences(of: "_", with: " "))"
            let bucket = ReportResult.GstBucket(id: label, label: label, amountPaise: netAmt)
            if c.sign > 0 { output.append(bucket) } else { input.append(bucket) }
            net = try CheckedMath.add(
                net,
                try CheckedMath.multiply(netAmt, Int64(c.sign), context: "calculating GST summary net payable"),
                context: "summing GST summary net payable"
            )
        }
        return ReportResult.GstSummary(
            fromDate: fromDate, toDate: toDate,
            output: output, input: input, netPayablePaise: net
        )
    }

    // MARK: - Day Book

    public func dayBook(fromDate: Date, toDate: Date, filter: ReportResult.ReportFilter) throws -> [ReportResult.DayBookRow] {
        let sql = """
            SELECT v.id, v.created_at, v.number, v.voucher_type_code, v.narration,
                   pa.name AS party_name,
                   COALESCE(SUM(CASE WHEN l.side = 'debit' THEN l.amount_paise ELSE 0 END), 0) AS total_debit,
                   COALESCE(SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END), 0) AS total_credit
            FROM avelo_vouchers v
            LEFT JOIN avelo_accounts pa ON pa.id = v.party_account_id
            LEFT JOIN avelo_ledger_lines l ON l.voucher_id = v.id AND l.company_id = v.company_id
            WHERE v.company_id = ? AND v.date BETWEEN ? AND ?
            GROUP BY v.id, v.created_at, v.number, v.voucher_type_code, v.narration, pa.name
            ORDER BY v.date ASC, v.created_at ASC, v.number ASC
        """
        return try db.query(sql, bind: [.text(filter.companyId.uuidString), .date(fromDate), .date(toDate)]) { r in
            return ReportResult.DayBookRow(
                id: try UUIDParsing.required(r.text("id"), field: "report.day_book.voucher_id"),
                timestamp: try r.timestamp("created_at"),
                voucherNumber: r.text("number"),
                voucherTypeCode: VoucherType.Code(rawValue: r.text("voucher_type_code")) ?? .journal,
                partyName: r.optionalText("party_name") ?? "",
                narration: r.text("narration"),
                totalDebitPaise: r.int("total_debit"),
                totalCreditPaise: r.int("total_credit")
            )
        }
    }

    // MARK: - Outstanding

    public func outstanding(asOfDate: Date, direction: ReportResult.OutstandingReport.Direction, filter: ReportResult.ReportFilter) throws -> ReportResult.OutstandingReport {
        let codes: [String]
        switch direction {
        case .receivable, .receivables: codes = ["SUNDRY_DEBTORS"]
        case .payable, .payables:      codes = ["SUNDRY_CREDITORS"]
        case .both:                    codes = ["SUNDRY_DEBTORS", "SUNDRY_CREDITORS"]
        }
        let placeholders = Array(repeating: "?", count: codes.count).joined(separator: ",")
        let sql = """
            SELECT a.id, a.name, a.code
            FROM avelo_accounts a
            WHERE a.company_id = ? AND a.code IN (\(placeholders)) AND a.is_active = 1
            ORDER BY a.code
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        for c in codes { bind.append(.text(c)) }
        let accounts: [(Account.ID, String, String)] = try db.query(sql, bind: bind) { r in
            (try UUIDParsing.required(r.text("id"), field: "report.outstanding.account_id"), r.text("name"), r.text("code"))
        }
        let accountIds = accounts.map { $0.0 }
        guard !accountIds.isEmpty else {
            return ReportResult.OutstandingReport(asOfDate: asOfDate, rows: [], direction: direction, totalPaise: 0)
        }
        let legacyTotals = try movementTotals(
            for: accountIds,
            companyId: filter.companyId,
            toDate: asOfDate
        )

        var rows: [ReportResult.OutstandingRow] = []
        for account in accounts {
            let totals = legacyTotals[account.0]
            let total = try CheckedMath.subtract(
                totals?.debitPaise ?? 0,
                totals?.creditPaise ?? 0,
                context: "calculating outstanding balance"
            )
            guard total != 0 else { continue }
            rows.append(ReportResult.OutstandingRow(
                id: account.0,
                partyName: account.1,
                asOf: asOfDate,
                amountPaise: total,
                age0to30Paise: total,
                ageInDays: 0
            ))
        }
        let total = try CheckedMath.sum(rows.map(\.amountPaise), context: "summing outstanding total")
        return ReportResult.OutstandingReport(asOfDate: asOfDate, rows: rows, direction: direction, totalPaise: total)
    }

    // MARK: - Stock Valuation

    public func stockValuation(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.StockValuationReport {
        let items = try InventoryRepository(db: db).listItemsForCompany(filter.companyId, includeInactive: false)
        guard !items.isEmpty else {
            return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: [])
        }
        let placeholders = Array(repeating: "?", count: items.count).joined(separator: ",")
        var bind: [SQLValue] = items.map { .text($0.id.uuidString) }
        bind.append(.date(asOfDate))
        struct StockTotals: Sendable {
            let inQty: Int64
            let outQty: Int64
            let inValuePaise: Int64
            let outValuePaise: Int64
            let onHandQty: Int64
        }
        let sql = """
            SELECT item_id,
                   COALESCE(SUM(CASE WHEN movement_type = 'in'
                                      THEN quantity ELSE 0 END), 0) AS in_q,
                   COALESCE(SUM(CASE WHEN movement_type = 'out'
                                      THEN quantity ELSE 0 END), 0) AS out_q,
                   COALESCE(SUM(CASE WHEN movement_type = 'in'
                                      THEN total_value_paise ELSE 0 END), 0) AS in_v,
                   COALESCE(SUM(CASE WHEN movement_type = 'out'
                                      THEN total_value_paise ELSE 0 END), 0) AS out_v,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' THEN quantity
                       WHEN movement_type = 'out' THEN -quantity
                       WHEN movement_type = 'adjustment' THEN quantity
                       ELSE 0 END), 0) AS on_hand
            FROM avelo_stock_movements
            WHERE item_id IN (\(placeholders)) AND date <= ?
            GROUP BY item_id
        """
        var totalsByItem: [InventoryItem.ID: StockTotals] = [:]
        _ = try db.query(sql, bind: bind) { row in
            let itemId = try UUIDParsing.required(row.text("item_id"), field: "report.stock_valuation.item_id")
            totalsByItem[itemId] = StockTotals(
                inQty: row.int("in_q"),
                outQty: row.int("out_q"),
                inValuePaise: row.int("in_v"),
                outValuePaise: row.int("out_v"),
                onHandQty: row.int("on_hand")
            )
        }
        let rows = try items.map { item in
            let totals = totalsByItem[item.id] ?? StockTotals(inQty: 0, outQty: 0, inValuePaise: 0, outValuePaise: 0, onHandQty: 0)
            let onHandValuePaise = try CheckedMath.subtract(
                totals.inValuePaise,
                totals.outValuePaise,
                context: "calculating stock valuation on-hand value"
            )
            let avg = totals.onHandQty > 0 ? onHandValuePaise / totals.onHandQty : 0
            return ReportResult.StockValuationRow(
                id: item.id,
                itemCode: item.code,
                itemName: item.name,
                unit: item.unit,
                quantity: Double(totals.onHandQty),
                ratePaise: avg,
                valuePaise: onHandValuePaise,
                openingQty: 0,
                openingValuePaise: 0,
                inQty: totals.inQty,
                inValuePaise: totals.inValuePaise,
                outQty: totals.outQty,
                outValuePaise: totals.outValuePaise,
                closingQty: totals.onHandQty,
                closingValuePaise: onHandValuePaise,
                averageCostPaise: avg
            )
        }
        return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: rows)
    }


    public func stockAgeing(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.StockAgeingReport {
        guard try CompanyRepository(db: db).findById(filter.companyId)?.isInventoryEnabled == true else {
            return ReportResult.StockAgeingReport(asOfDate: asOfDate, rows: [])
        }
        let items = try InventoryRepository(db: db).listItemsForCompany(filter.companyId, includeInactive: false)
        guard !items.isEmpty else {
            return ReportResult.StockAgeingReport(asOfDate: asOfDate, rows: [])
        }
        let placeholders = Array(repeating: "?", count: items.count).joined(separator: ",")
        var bind: [SQLValue] = items.map { .text($0.id.uuidString) }
        bind.append(.date(asOfDate))
        let sql = """
            SELECT item_id,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' AND julianday(?) - julianday(date) BETWEEN 0 AND 30 THEN quantity
                       ELSE 0 END), 0) AS age_0_30,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' AND julianday(?) - julianday(date) BETWEEN 31 AND 60 THEN quantity
                       ELSE 0 END), 0) AS age_31_60,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' AND julianday(?) - julianday(date) BETWEEN 61 AND 90 THEN quantity
                       ELSE 0 END), 0) AS age_61_90,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' AND julianday(?) - julianday(date) > 90 THEN quantity
                       ELSE 0 END), 0) AS age_90_plus,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' THEN quantity
                       WHEN movement_type = 'out' THEN -quantity
                       WHEN movement_type = 'adjustment' THEN quantity
                       ELSE 0 END), 0) AS on_hand,
                   COALESCE(SUM(CASE
                       WHEN movement_type = 'in' THEN total_value_paise
                       WHEN movement_type = 'out' THEN -total_value_paise
                       ELSE 0 END), 0) AS value_paise
            FROM avelo_stock_movements
            WHERE item_id IN (\(placeholders)) AND date <= ?
            GROUP BY item_id
        """
        var ageingBind: [SQLValue] = [.date(asOfDate), .date(asOfDate), .date(asOfDate), .date(asOfDate)]
        ageingBind.append(contentsOf: bind)
        var rowsByItem: [InventoryItem.ID: ReportResult.StockAgeingRow] = [:]
        _ = try db.query(sql, bind: ageingBind) { row in
            let itemId = try UUIDParsing.required(row.text("item_id"), field: "report.stock_ageing.item_id")
            guard let item = items.first(where: { $0.id == itemId }) else { return }
            let onHand = row.int("on_hand")
            if onHand <= 0 { return }
            rowsByItem[itemId] = ReportResult.StockAgeingRow(
                id: itemId,
                itemCode: item.code,
                itemName: item.name,
                unit: item.unit,
                onHandQty: onHand,
                onHandValuePaise: row.int("value_paise"),
                age0to30Qty: row.int("age_0_30"),
                age31to60Qty: row.int("age_31_60"),
                age61to90Qty: row.int("age_61_90"),
                age90PlusQty: row.int("age_90_plus")
            )
        }
        let rows = items.compactMap { rowsByItem[$0.id] }
        return ReportResult.StockAgeingReport(asOfDate: asOfDate, rows: rows)
    }
}
