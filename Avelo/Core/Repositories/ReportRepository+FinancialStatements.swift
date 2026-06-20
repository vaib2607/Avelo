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
}
