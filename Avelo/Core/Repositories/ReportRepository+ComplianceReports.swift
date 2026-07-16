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
                id: try UUIDParsing.required(r.requiredText("id"), field: "report.day_book.voucher_id"),
                timestamp: try r.timestamp("created_at"),
                voucherNumber: try r.requiredText("number"),
                voucherTypeCode: try r.enumValue("voucher_type_code"),
                partyName: try r.checkedOptionalText("party_name") ?? "",
                narration: try r.requiredText("narration"),
                totalDebitPaise: try r.requiredInt("total_debit"),
                totalCreditPaise: try r.requiredInt("total_credit")
            )
        }
    }

    // MARK: - Outstanding

    public func outstanding(asOfDate: Date, direction: ReportResult.OutstandingReport.Direction, filter: ReportResult.ReportFilter) throws -> ReportResult.OutstandingReport {
        let events = try outstandingEvents(asOfDate: asOfDate, filter: filter)
        guard !events.isEmpty else {
            return ReportResult.OutstandingReport(asOfDate: asOfDate, rows: [], direction: direction, totalPaise: 0)
        }
        let settled = try BillAllocationEngine.settle(events: events, asOfDate: asOfDate)
        var rows: [ReportResult.OutstandingRow] = []
        for item in settled {
            guard includeOutstanding(item.remainingPaise, for: direction) else { continue }
            let ageInDays = max(0, DateFormatters.utcCalendar.dateComponents([.day], from: item.originDate, to: asOfDate).day ?? 0)
            let buckets = ageingBuckets(amountPaise: item.remainingPaise, ageInDays: ageInDays)
            rows.append(ReportResult.OutstandingRow(
                id: item.id,
                accountId: item.accountId,
                partyName: item.partyName,
                referenceNumber: item.referenceNumber,
                asOf: asOfDate,
                amountPaise: item.remainingPaise,
                age0to30Paise: buckets.age0to30Paise,
                age31to60Paise: buckets.age31to60Paise,
                age61to90Paise: buckets.age61to90Paise,
                age90PlusPaise: buckets.age90PlusPaise,
                ageInDays: ageInDays
            ))
        }
        let total = try CheckedMath.sum(rows.map(\.amountPaise), context: "summing outstanding total")
        return ReportResult.OutstandingReport(asOfDate: asOfDate, rows: rows, direction: direction, totalPaise: total)
    }

    private func outstandingEvents(asOfDate: Date,
                                   filter: ReportResult.ReportFilter) throws -> [BillAllocationEvent] {
        try db.query(
            """
            SELECT
                ba.id,
                ba.company_id,
                ba.voucher_id,
                ba.party_account_id,
                ba.kind,
                ba.reference_number,
                ba.allocated_paise,
                ba.created_at,
                v.number AS voucher_number,
                v.date AS voucher_date,
                v.created_at AS voucher_created_at,
                a.name AS party_name,
                l.side AS party_side
            FROM avelo_bill_allocations ba
            JOIN avelo_vouchers v ON v.id = ba.voucher_id AND v.company_id = ba.company_id
            JOIN avelo_accounts a ON a.id = ba.party_account_id AND a.company_id = ba.company_id
            JOIN avelo_ledger_lines l ON l.voucher_id = ba.voucher_id
                AND l.company_id = ba.company_id
                AND l.account_id = ba.party_account_id
            WHERE ba.company_id = ?
              AND v.date <= ?
            ORDER BY v.date ASC, v.created_at ASC, v.number ASC, ba.created_at ASC, ba.id ASC
            """,
            bind: [.text(filter.companyId.uuidString), .date(asOfDate)]
        ) { row in
            let allocation = try BillAllocation(
                id: UUIDParsing.required(row.requiredText("id"), field: "report.outstanding.bill_allocation_id"),
                companyId: UUIDParsing.required(row.requiredText("company_id"), field: "report.outstanding.company_id"),
                voucherId: UUIDParsing.required(row.requiredText("voucher_id"), field: "report.outstanding.voucher_id"),
                partyAccountId: UUIDParsing.required(row.requiredText("party_account_id"), field: "report.outstanding.party_account_id"),
                kind: row.enumValue("kind"),
                referenceNumber: row.checkedOptionalText("reference_number"),
                allocatedPaise: row.requiredInt("allocated_paise"),
                createdAt: row.timestamp("created_at")
            )
            let signedPaise = try row.requiredText("party_side") == EntrySide.debit.rawValue
                ? allocation.allocatedPaise
                : CheckedMath.multiply(allocation.allocatedPaise, -1, context: "signing bill allocation from party side")
            return BillAllocationEvent(
                allocation: allocation,
                voucherId: allocation.voucherId,
                accountId: allocation.partyAccountId,
                partyName: try row.requiredText("party_name"),
                voucherNumber: try row.requiredText("voucher_number"),
                voucherDate: try row.requiredDate("voucher_date"),
                voucherCreatedAt: try row.timestamp("voucher_created_at"),
                signedPaise: signedPaise
            )
        }
    }

    private func includeOutstanding(_ amountPaise: Int64,
                                    for direction: ReportResult.OutstandingReport.Direction) -> Bool {
        switch direction {
        case .receivable, .receivables:
            return amountPaise > 0
        case .payable, .payables:
            return amountPaise < 0
        case .both:
            return amountPaise != 0
        }
    }

    private func ageingBuckets(amountPaise: Int64,
                               ageInDays: Int) -> (age0to30Paise: Int64, age31to60Paise: Int64, age61to90Paise: Int64, age90PlusPaise: Int64) {
        switch ageInDays {
        case 0...30:
            return (amountPaise, 0, 0, 0)
        case 31...60:
            return (0, amountPaise, 0, 0)
        case 61...90:
            return (0, 0, amountPaise, 0)
        default:
            return (0, 0, 0, amountPaise)
        }
    }

    // MARK: - Stock Valuation

    public func stockValuation(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.StockValuationReport {
        // AVL-P0-033: unlike its sibling stockAgeing, this had no gate at
        // all — real stock value leaked into Reports and the Dashboard KPI
        // even when the company has inventory disabled.
        guard try CompanyRepository(db: db).findById(filter.companyId)?.isInventoryEnabled == true else {
            return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: [])
        }
        let inventory = InventoryRepository(db: db)
        let items = try inventory.listItemsForCompany(filter.companyId, includeInactive: false)
        guard !items.isEmpty else {
            return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: [])
        }
        let rows = try items.map { item in
            let totals = try inventory.runningBalance(itemId: item.id, asOf: asOfDate)
            let onHandValuePaise = totals.onHandValuePaise
            let onHandWholeQty = totals.onHandQuantity.magnitude.wholeValue ?? 0
            let avg = onHandWholeQty > 0 ? onHandValuePaise / onHandWholeQty : 0
            let zeroQuantity = try ExactQuantity.whole(0)
            let closingQuantity = totals.onHandQuantity.isZero ? zeroQuantity : totals.onHandQuantity.magnitude
            return ReportResult.StockValuationRow(
                id: item.id,
                itemCode: item.code,
                itemName: item.name,
                unit: item.unit,
                quantity: closingQuantity,
                ratePaise: avg,
                valuePaise: onHandValuePaise,
                openingQty: zeroQuantity,
                openingValuePaise: 0,
                inQty: totals.inQuantity,
                inValuePaise: totals.inValuePaise,
                outQty: totals.outQuantity,
                outValuePaise: totals.outValuePaise,
                closingQty: closingQuantity,
                closingValuePaise: onHandValuePaise,
                averageCostPaise: avg
            )
        }
        let total = try CheckedMath.sum(rows.map { $0.valuePaise }, context: "summing stock valuation report total")
        return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: rows, totalPaise: total)
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
