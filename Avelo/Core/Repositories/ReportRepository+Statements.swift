import Foundation

extension ReportRepository {

    // MARK: - P&L

    public func profitAndLoss(fromDate: Date, toDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.ProfitLoss {
        let groups = try AccountGroupRepository(db: db).listForCompany(filter.companyId)
        let groupById: [UUID: AccountGroup] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        let directIncome = try sectionRows(filter: filter, fromDate: fromDate, toDate: toDate, nature: .income, rootCodes: ["DIRECT_INCOME"], groupById: groupById)
        let indirectIncome = try sectionRows(filter: filter, fromDate: fromDate, toDate: toDate, nature: .income, rootCodes: ["INDIRECT_INCOME"], groupById: groupById)
        let directExpense = try sectionRows(filter: filter, fromDate: fromDate, toDate: toDate, nature: .expense, rootCodes: ["DIRECT_EXPENSE"], groupById: groupById)
        let indirectExpense = try sectionRows(filter: filter, fromDate: fromDate, toDate: toDate, nature: .expense, rootCodes: ["INDIRECT_EXPENSE"], groupById: groupById)

        let ti = directIncome.totalPaise + indirectIncome.totalPaise
        let te = directExpense.totalPaise + indirectExpense.totalPaise
        assert(ti <= Int64.max / 2)
        assert(te <= Int64.max / 2)
        return ReportResult.ProfitLoss(
            fromDate: fromDate, toDate: toDate,
            directIncome: directIncome,
            indirectIncome: indirectIncome,
            directExpense: directExpense,
            indirectExpense: indirectExpense,
            totalIncomePaise: ti,
            totalExpensePaise: te,
            netProfitPaise: ti - te
        )
    }

    private func sectionRows(filter: ReportResult.ReportFilter,
                             fromDate: Date,
                             toDate: Date,
                             nature: AccountNature,
                             rootCodes: [String],
                             groupById: [AccountGroup.ID: AccountGroup]) throws -> ReportResult.ProfitLossSection {
        let groupIds = groupsWithNature(nature: nature, rootCodes: rootCodes, allGroups: Array(groupById.values))
        let placeholders = Array(repeating: "?", count: groupIds.count).joined(separator: ",")
        var sql = """
            SELECT a.id, a.code, a.name, a.opening_balance_paise AS ob, a.opening_balance_side AS obs,
                   g.code AS gcode
            FROM avelo_accounts a
            JOIN avelo_account_groups g ON g.id = a.group_id
            WHERE a.company_id = ? AND a.is_active = 1
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if !groupIds.isEmpty {
            sql += " AND a.group_id IN (\(placeholders))"
            for gid in groupIds { bind.append(.text(gid.uuidString)) }
        } else {
            return ReportResult.ProfitLossSection(title: rootCodes.joined(separator: "/"), rows: [], totalPaise: 0)
        }
        sql += " ORDER BY g.sort_order, g.code, a.code"
        let raws: [(Account.ID, String, String, Int64, String, String)] = try db.query(sql, bind: bind) { r in
            (
                try UUIDParsing.required(r.text("id"), field: "report.profit_loss.account_id"),
                r.text("code"),
                r.text("name"),
                r.int("ob"),
                r.text("obs"),
                r.text("gcode")
            )
        }
        let totalsByAccount = try movementTotals(
            for: raws.map { $0.0 },
            companyId: filter.companyId,
            fromDate: fromDate,
            toDate: toDate
        )
        var rows: [ReportResult.TrialBalanceRow] = []
        var sectionTotal: Int64 = 0
        for (id, code, name, ob, obs, gcode) in raws {
            let move = totalsByAccount[id]
            let dr = move?.debitPaise ?? 0
            let cr = move?.creditPaise ?? 0
            let signedOpening: Int64 = obs == "debit" ? ob : -ob
            let absNet: Int64
            switch nature {
            case .income:
                absNet = cr - dr - (signedOpening < 0 ? -signedOpening : 0) + (signedOpening > 0 ? signedOpening : 0)
            case .expense:
                absNet = dr - cr + (signedOpening > 0 ? signedOpening : 0) - (signedOpening < 0 ? -signedOpening : 0)
            case .assets, .liabilities:
                absNet = 0
            }
            sectionTotal += absNet
            assert(sectionTotal <= Int64.max / 2)
            rows.append(ReportResult.TrialBalanceRow(
                id: id, accountCode: code, accountName: name, groupPath: gcode,
                debitPaise: 0, creditPaise: 0
            ))
        }
        return ReportResult.ProfitLossSection(title: rootCodes.joined(separator: "/"), rows: rows, totalPaise: sectionTotal)
    }

    private func groupsWithNature(nature: AccountNature, rootCodes: [String], allGroups: [AccountGroup]) -> [UUID] {
        let roots = allGroups.filter { $0.nature == nature && rootCodes.contains($0.code) }
        let rootIds = Set(roots.map { $0.id })
        var result = Set<UUID>()
        var stack: [AccountGroup] = roots
        while let g = stack.popLast() {
            result.insert(g.id)
            for child in allGroups where child.parentGroupId == g.id {
                stack.append(child)
            }
        }
        _ = rootIds
        return Array(result)
    }

    // MARK: - Balance Sheet

    public func balanceSheet(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.BalanceSheet {
        let groups = try AccountGroupRepository(db: db).listForCompany(filter.companyId)
        let groupById: [UUID: AccountGroup] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        let assetCodes = ["FIXED_ASSETS", "INVESTMENTS", "CURRENT_ASSETS", "STOCK_IN_HAND", "BANK_ACCOUNTS"]
        let liabilityCodes = ["CAPITAL", "LOANS", "CURRENT_LIAB", "DUTIES_TAXES"]
        let assetSections = try bsSections(filter: filter, asOfDate: asOfDate, nature: .assets, rootCodes: assetCodes, groupById: groupById)
        let liabSections = try bsSections(filter: filter, asOfDate: asOfDate, nature: .liabilities, rootCodes: liabilityCodes, groupById: groupById)
        let totalAssets = assetSections.reduce(0) { $0 + $1.totalPaise }
        let totalLiab = liabSections.reduce(0) { $0 + $1.totalPaise }
        assert(totalAssets <= Int64.max / 2)
        assert(totalLiab <= Int64.max / 2)
        let equity = totalAssets - totalLiab
        return ReportResult.BalanceSheet(
            asOfDate: asOfDate,
            assets: assetSections,
            liabilities: liabSections,
            equity: [],
            totalAssetsPaise: totalAssets,
            totalLiabilitiesPaise: totalLiab,
            totalEquityPaise: equity,
            balancingEquityPaise: equity
        )
    }

    private func bsSections(filter: ReportResult.ReportFilter,
                            asOfDate: Date,
                            nature: AccountNature,
                            rootCodes: [String],
                            groupById: [AccountGroup.ID: AccountGroup]) throws -> [ReportResult.BalanceSheetSection] {
        let groupIds = groupsWithNature(nature: nature, rootCodes: rootCodes, allGroups: Array(groupById.values))
        let placeholders = Array(repeating: "?", count: groupIds.count).joined(separator: ",")
        var sql = """
            SELECT a.id, a.code, a.name, a.opening_balance_paise AS ob, a.opening_balance_side AS obs,
                   g.code AS gcode, g.name AS gname
            FROM avelo_accounts a
            JOIN avelo_account_groups g ON g.id = a.group_id
            WHERE a.company_id = ? AND a.is_active = 1
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if groupIds.isEmpty { return [] }
        sql += " AND a.group_id IN (\(placeholders))"
        for gid in groupIds { bind.append(.text(gid.uuidString)) }
        sql += " ORDER BY g.sort_order, g.code, a.code"
        let raws: [(Account.ID, String, String, Int64, String, String, String)] = try db.query(sql, bind: bind) { r in
            (
                try UUIDParsing.required(r.text("id"), field: "report.balance_sheet.account_id"),
                r.text("code"),
                r.text("name"),
                r.int("ob"),
                r.text("obs"),
                r.text("gcode"),
                r.text("gname")
            )
        }
        let totalsByAccount = try movementTotals(
            for: raws.map { $0.0 },
            companyId: filter.companyId,
            toDate: asOfDate
        )
        var byGname: [String: [ReportResult.TrialBalanceRow]] = [:]
        var totals: [String: Int64] = [:]
        for (id, code, name, ob, obs, gcode, gname) in raws {
            let move = totalsByAccount[id]
            let dr = move?.debitPaise ?? 0
            let cr = move?.creditPaise ?? 0
            let signedOpening: Int64 = obs == "debit" ? ob : -ob
            let net: Int64
            if nature == .assets {
                net = dr - cr + signedOpening
            } else {
                net = cr - dr - signedOpening
            }
            if net == 0 { continue }
            let row = ReportResult.TrialBalanceRow(
                id: id, accountCode: code, accountName: name, groupPath: gcode,
                debitPaise: net > 0 ? net : 0,
                creditPaise: net < 0 ? -net : 0
            )
            byGname[gname, default: []].append(row)
            totals[gname, default: 0] += net
            assert(totals[gname, default: 0] <= Int64.max / 2)
        }
        return byGname.keys.sorted().map { gname in
            ReportResult.BalanceSheetSection(id: gname, title: gname, rows: byGname[gname] ?? [], totalPaise: totals[gname] ?? 0)
        }
    }

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
            let netAmt = c.sign > 0 ? cr - dr : dr - cr
            assert(netAmt <= Int64.max / 2)
            let label = "\(c.accountCode.replacingOccurrences(of: "_", with: " "))"
            let bucket = ReportResult.GstBucket(id: label, label: label, amountPaise: netAmt)
            if c.sign > 0 { output.append(bucket) } else { input.append(bucket) }
            net += netAmt * Int64(c.sign)
            assert(net <= Int64.max / 2)
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
            let total = (totals?.debitPaise ?? 0) - (totals?.creditPaise ?? 0)
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
        let total = rows.reduce(0) { $0 + $1.amountPaise }
        assert(total <= Int64.max / 2)
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
        let rows = items.map { item in
            let totals = totalsByItem[item.id] ?? StockTotals(inQty: 0, outQty: 0, inValuePaise: 0, outValuePaise: 0, onHandQty: 0)
            let onHandValuePaise = totals.inValuePaise - totals.outValuePaise
            assert(onHandValuePaise <= Int64.max / 2)
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

    public func cashFlow(fromDate: Date, toDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.CashFlowStatement {
        let sql = """
            WITH cash_lines AS (
                SELECT l.voucher_id, l.side, l.amount_paise
                FROM avelo_ledger_lines l
                JOIN avelo_accounts a ON a.id = l.account_id
                JOIN avelo_vouchers v ON v.id = l.voucher_id
                WHERE l.company_id = ?
                  AND v.company_id = ?
                  AND v.is_posted = 1
                  AND v.date BETWEEN ? AND ?
                  AND (UPPER(a.code) LIKE '%CASH%' OR UPPER(a.code) LIKE '%BANK%')
            )
            SELECT a.code,
                   a.name,
                   g.nature,
                   COALESCE(SUM(CASE
                       WHEN cl.side = 'debit' AND l.side = 'credit' THEN l.amount_paise
                       ELSE 0 END), 0) AS inflow,
                   COALESCE(SUM(CASE
                       WHEN cl.side = 'credit' AND l.side = 'debit' THEN l.amount_paise
                       ELSE 0 END), 0) AS outflow
            FROM cash_lines cl
            JOIN avelo_ledger_lines l ON l.voucher_id = cl.voucher_id AND l.company_id = ?
            JOIN avelo_accounts a ON a.id = l.account_id
            JOIN avelo_account_groups g ON g.id = a.group_id
            WHERE NOT (UPPER(a.code) LIKE '%CASH%' OR UPPER(a.code) LIKE '%BANK%')
            GROUP BY a.id, a.code, a.name, g.nature
            HAVING inflow != 0 OR outflow != 0
            ORDER BY g.nature, a.code
        """
        var operating: Int64 = 0
        var investing: Int64 = 0
        var financing: Int64 = 0
        let rows = try db.query(
            sql,
            bind: [
                .text(filter.companyId.uuidString),
                .text(filter.companyId.uuidString),
                .date(fromDate),
                .date(toDate),
                .text(filter.companyId.uuidString)
            ]
        ) { row in
            let nature = AccountNature(rawValue: row.text("nature")) ?? .expense
            let section: ReportResult.CashFlowRow.Section
            switch nature {
            case .assets:
                section = .investing
            case .liabilities:
                section = .financing
            case .income, .expense:
                section = .operating
            }
            let inflow = row.int("inflow")
            let outflow = row.int("outflow")
            let net = inflow - outflow
            switch section {
            case .operating: operating += net
            case .investing: investing += net
            case .financing: financing += net
            }
            return ReportResult.CashFlowRow(
                id: "\(section.rawValue)-\(row.text("code"))",
                section: section,
                accountCode: row.text("code"),
                accountName: row.text("name"),
                inflowPaise: inflow,
                outflowPaise: outflow,
                netPaise: net
            )
        }
        let net = operating + investing + financing
        assert(net <= Int64.max / 2)
        return ReportResult.CashFlowStatement(
            fromDate: fromDate,
            toDate: toDate,
            rows: rows,
            operatingNetPaise: operating,
            investingNetPaise: investing,
            financingNetPaise: financing,
            netCashFlowPaise: net
        )
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
