import Foundation

public struct ReportRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    private struct MovementTotals: Sendable {
        let debitPaise: Int64
        let creditPaise: Int64
    }

    private func movementTotals(
        for accountIds: [Account.ID],
        companyId: Company.ID,
        fromDate: Date? = nil,
        toDate: Date? = nil
    ) throws -> [Account.ID: MovementTotals] {
        guard !accountIds.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: accountIds.count).joined(separator: ",")
        var sql = """
            SELECT l.account_id AS aid,
                   COALESCE(SUM(CASE WHEN l.side='debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN l.side='credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE l.company_id = ? AND l.account_id IN (\(placeholders))
        """
        var bind: [SQLValue] = [.text(companyId.uuidString)]
        for id in accountIds {
            bind.append(.text(id.uuidString))
        }
        if let fromDate {
            sql += " AND v.date >= ?"
            bind.append(.date(fromDate))
        }
        if let toDate {
            sql += " AND v.date <= ?"
            bind.append(.date(toDate))
        }
        sql += " GROUP BY l.account_id"
        var out: [Account.ID: MovementTotals] = [:]
        _ = try db.query(sql, bind: bind) { row in
            if let idStr = row.optionalText("aid"), let id = UUID(uuidString: idStr) {
                out[id] = MovementTotals(debitPaise: row.int("dr"), creditPaise: row.int("cr"))
            }
        }
        return out
    }

    // MARK: - Ledger

    public func ledgerReport(filter: ReportResult.ReportFilter,
                             accountId: Account.ID) throws -> ReportResult.LedgerReport {
        let account = try AccountRepository(db: db).findById(accountId)
        let accountName = account?.name ?? "Unknown"
        let groupNature = (try account.flatMap { try AccountGroupRepository(db: db).findById($0.groupId) })?.nature ?? .assets
        let normalSide = groupNature.normalBalance
        let signedOpening: Int64 = (account?.signedOpeningBalancePaise() ?? 0) * (normalSide == .debit ? 1 : 1)

        var sql = """
            SELECT v.id AS vid, v.date AS vdate, v.number AS vnum, v.voucher_type_code AS vtype,
                   v.narration AS vnarration, l.amount_paise AS amt, l.side AS lside, l.line_order AS ord
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id
            WHERE l.company_id = ? AND l.account_id = ?
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString), .text(accountId.uuidString)]
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
        sql += " ORDER BY v.date ASC, v.created_at ASC, l.line_order ASC"

        let rawRows: [(Voucher.ID, Date, String, VoucherType.Code, String, Int64, EntrySide, Int)] = try db.query(sql, bind: bind) { r in
            (
                try UUIDParsing.required(r.text("vid"), field: "report.ledger.voucher_id"),
                r.date("vdate"),
                r.text("vnum"),
                VoucherType.Code(rawValue: r.text("vtype")) ?? .journal,
                r.text("vnarration"),
                r.int("amt"),
                EntrySide(rawValue: r.text("lside")) ?? .debit,
                Int(r.int("ord"))
            )
        }

        var running = signedOpening
        var rows: [ReportResult.LedgerRow] = []
        for (vid, date, num, type, narr, amt, side, _) in rawRows {
            if side == .debit {
                running += amt
            } else {
                running -= amt
            }
            rows.append(ReportResult.LedgerRow(
                date: date,
                voucherNumber: num,
                voucherTypeCode: type,
                narration: narr,
                debitPaise: side == .debit ? amt : 0,
                creditPaise: side == .credit ? amt : 0,
                balancePaise: running,
                voucherId: vid
            ))
        }
        return ReportResult.LedgerReport(
            accountId: accountId,
            accountName: accountName,
            openingBalancePaise: signedOpening,
            rows: rows,
            closingBalancePaise: running
        )
    }

    // MARK: - Trial Balance

    public func trialBalance(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.TrialBalance {
        let asOfStr = DateFormatters.formatIsoDate(asOfDate)
        let sql = """
            WITH movements AS (
                SELECT l.account_id AS aid,
                       SUM(CASE WHEN l.side = 'debit'  THEN l.amount_paise ELSE 0 END) AS dr,
                       SUM(CASE WHEN l.side = 'credit' THEN l.amount_paise ELSE 0 END) AS cr
                FROM avelo_ledger_lines l
                JOIN avelo_vouchers v ON v.id = l.voucher_id
                WHERE l.company_id = ? AND v.date <= ?
                GROUP BY l.account_id
            ),
            opening AS (
                SELECT a.id AS aid, a.opening_balance_paise AS ob, a.opening_balance_side AS obs
                FROM avelo_accounts a
                WHERE a.company_id = ?
            )
            SELECT a.id AS aid, a.code AS acode, a.name AS aname,
                   a.opening_balance_paise AS ob, a.opening_balance_side AS obs,
                   g.code AS gcode, g.name AS gname, g.parent_group_id AS parent
            FROM avelo_accounts a
            JOIN avelo_account_groups g ON g.id = a.group_id
            WHERE a.company_id = ?
              AND a.is_active = 1
            ORDER BY g.sort_order, g.code, a.code
        """
        let bind: [SQLValue] = [
            .text(filter.companyId.uuidString), .text(asOfStr),
            .text(filter.companyId.uuidString),
            .text(filter.companyId.uuidString)
        ]
        struct Raw: Sendable { let id: Account.ID; let code: String; let name: String; let ob: Int64; let obs: String; let gcode: String; let gname: String; let parent: String? }
        let raws: [Raw] = try db.query(sql, bind: bind) { r in
            Raw(
                id: try UUIDParsing.required(r.text("aid"), field: "report.trial_balance.account_id"),
                code: r.text("acode"),
                name: r.text("aname"),
                ob: r.int("ob"),
                obs: r.text("obs"),
                gcode: r.text("gcode"),
                gname: r.text("gname"),
                parent: r.optionalText("parent")
            )
        }
        let groups = try AccountGroupRepository(db: db).listForCompany(filter.companyId)
        let groupById: [UUID: AccountGroup] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let totalsByAccount = try movementTotals(
            for: raws.map(\.id),
            companyId: filter.companyId,
            toDate: asOfDate
        )

        var rows: [ReportResult.TrialBalanceRow] = []
        var totalDr: Int64 = 0
        var totalCr: Int64 = 0
        for raw in raws {
            let movement = totalsByAccount[raw.id]
            let moveDr = movement?.debitPaise ?? 0
            let moveCr = movement?.creditPaise ?? 0
            let signedOpening: Int64 = raw.obs == "debit" ? raw.ob : -raw.ob
            let netDebit = (signedOpening > 0 ? signedOpening : 0) + moveDr
            let netCredit = (signedOpening < 0 ? -signedOpening : 0) + moveCr
            let groupPath = groupPathText(for: raw.gcode, groups: groupById)
            rows.append(ReportResult.TrialBalanceRow(
                id: raw.id,
                accountCode: raw.code,
                accountName: raw.name,
                groupPath: groupPath,
                debitPaise: netDebit,
                creditPaise: netCredit
            ))
            totalDr += netDebit
            totalCr += netCredit
            assert(totalDr <= Int64.max / 2)
            assert(totalCr <= Int64.max / 2)
        }
        return ReportResult.TrialBalance(
            asOfDate: asOfDate,
            rows: rows,
            totalDebitPaise: totalDr,
            totalCreditPaise: totalCr
        )
    }

    private func groupPathText(for groupCode: String, groups: [AccountGroup.ID: AccountGroup]) -> String {
        _ = groups
        return groupCode
    }

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
            let netAmt: Int64
            if acct.openingBalanceSide == .debit {
                netAmt = (dr + acct.openingBalancePaise) - cr
            } else {
                netAmt = (cr + acct.openingBalancePaise) - dr
            }
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
            SELECT v.id, v.created_at, v.number, v.voucher_type_code, v.narration, v.total_paise,
                   pa.name AS party_name
            FROM avelo_vouchers v
            LEFT JOIN avelo_accounts pa ON pa.id = v.party_account_id
            WHERE v.company_id = ? AND v.date BETWEEN ? AND ?
            ORDER BY v.date ASC, v.created_at ASC, v.number ASC
        """
        return try db.query(sql, bind: [.text(filter.companyId.uuidString), .date(fromDate), .date(toDate)]) { r in
            let total = r.int("total_paise")
            let half = total / 2
            return ReportResult.DayBookRow(
                id: try UUIDParsing.required(r.text("id"), field: "report.day_book.voucher_id"),
                timestamp: try r.timestamp("created_at"),
                voucherNumber: r.text("number"),
                voucherTypeCode: VoucherType.Code(rawValue: r.text("voucher_type_code")) ?? .journal,
                partyName: r.optionalText("party_name") ?? "",
                narration: r.text("narration"),
                totalDebitPaise: half,
                totalCreditPaise: total - half
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
        let placeholder = Array(repeating: "?", count: accountIds.count).joined(separator: ",")
        let billSql = """
            SELECT ba.party_account_id AS aid,
                   ba.kind AS kind,
                   COALESCE(ba.reference_number, v.number) AS ref,
                   ba.allocated_paise AS allocated,
                   v.date AS vdate
            FROM avelo_bill_allocations ba
            JOIN avelo_vouchers v ON v.id = ba.voucher_id AND v.company_id = ba.company_id
            WHERE ba.company_id = ? AND ba.party_account_id IN (\(placeholder)) AND v.date <= ?
            ORDER BY v.date ASC, v.created_at ASC
        """
        struct BillRow: Sendable {
            let partyId: Account.ID
            let kind: BillAllocationKind
            let reference: String
            let allocatedPaise: Int64
            let voucherDate: Date
        }
        let billRows: [BillRow] = try db.query(billSql, bind: [.text(filter.companyId.uuidString)] + accountIds.map { .text($0.uuidString) } + [.date(asOfDate)]) { r in
            BillRow(
                partyId: try UUIDParsing.required(r.text("aid"), field: "report.outstanding.party_account_id"),
                kind: BillAllocationKind(rawValue: r.text("kind")) ?? .newRef,
                reference: r.text("ref"),
                allocatedPaise: r.int("allocated"),
                voucherDate: r.date("vdate")
            )
        }
        let legacyTotals = try movementTotals(
            for: accountIds,
            companyId: filter.companyId,
            toDate: asOfDate
        )

        struct BillSummary {
            var accountName: String
            var totalPaise: Int64 = 0
            var age0to30Paise: Int64 = 0
            var age31to60Paise: Int64 = 0
            var age61to90Paise: Int64 = 0
            var age90PlusPaise: Int64 = 0
            var ageInDays: Int = 0
            var invoices: [String: (date: Date, amount: Int64)] = [:]
            var settlements: [String: Int64] = [:]
        }

        var summaries: [Account.ID: BillSummary] = Dictionary(uniqueKeysWithValues: accounts.map { ($0.0, BillSummary(accountName: $0.1)) })
        for bill in billRows {
            guard var summary = summaries[bill.partyId] else { continue }
            switch bill.kind {
            case .newRef:
                let entry = summary.invoices[bill.reference] ?? (date: bill.voucherDate, amount: 0)
                summary.invoices[bill.reference] = (date: min(entry.date, bill.voucherDate), amount: entry.amount + bill.allocatedPaise)
            case .agstRef:
                summary.settlements[bill.reference, default: 0] += bill.allocatedPaise
            case .advance, .onAccount:
                break
            }
            summaries[bill.partyId] = summary
        }

        var rows: [ReportResult.OutstandingRow] = []
        for (aid, summary) in summaries {
            if summary.invoices.isEmpty && summary.settlements.isEmpty {
                let totals = legacyTotals[aid]
                let total = (totals?.debitPaise ?? 0) - (totals?.creditPaise ?? 0)
                if total == 0 { continue }
                if let account = accounts.first(where: { $0.0 == aid }) {
                    rows.append(ReportResult.OutstandingRow(
                        id: aid,
                        partyName: account.1,
                        asOf: asOfDate,
                        amountPaise: total,
                        age0to30Paise: total,
                        ageInDays: 0
                    ))
                }
                continue
            }
            var total: Int64 = 0
            var bucket0: Int64 = 0
            var bucket31: Int64 = 0
            var bucket61: Int64 = 0
            var bucket90: Int64 = 0
            var maxAge = 0
            for (ref, invoice) in summary.invoices {
                let settled = summary.settlements[ref, default: 0]
                let outstanding = invoice.amount - settled
                guard outstanding > 0 else { continue }
                total += outstanding
                let days = max(0, Int(asOfDate.timeIntervalSince(invoice.date) / 86_400))
                maxAge = max(maxAge, days)
                switch days {
                case 0...30: bucket0 += outstanding
                case 31...60: bucket31 += outstanding
                case 61...90: bucket61 += outstanding
                default: bucket90 += outstanding
                }
            }
            guard total > 0 else { continue }
            rows.append(ReportResult.OutstandingRow(
                id: aid,
                partyName: summary.accountName,
                asOf: asOfDate,
                amountPaise: total,
                age0to30Paise: bucket0,
                age31to60Paise: bucket31,
                age61to90Paise: bucket61,
                age90PlusPaise: bucket90,
                ageInDays: maxAge
            ))
        }
        let total = rows.reduce(0) { $0 + $1.amountPaise }
        assert(total <= Int64.max / 2)
        return ReportResult.OutstandingReport(asOfDate: asOfDate, rows: rows, direction: direction, totalPaise: total)
    }

    // MARK: - Stock Valuation

    public func stockValuation(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.StockValuationReport {
        let items = try InventoryRepository(db: db).listItemsForCompany(filter.companyId, includeInactive: false)
        let repo = InventoryRepository(db: db)
        var rows: [ReportResult.StockValuationRow] = []
        for item in items {
            let bal = try repo.runningBalance(itemId: item.id, asOf: asOfDate)
            let avg = bal.onHandQty > 0 ? Int64((Double(bal.onHandValuePaise) / bal.onHandQty).rounded()) : 0
            rows.append(ReportResult.StockValuationRow(
                id: item.id,
                itemCode: item.code,
                itemName: item.name,
                unit: item.unit,
                quantity: bal.onHandQty,
                ratePaise: avg,
                valuePaise: bal.onHandValuePaise,
                openingQty: 0,
                openingValuePaise: 0,
                inQty: Int64(bal.inQty.rounded()),
                inValuePaise: bal.inValuePaise,
                outQty: Int64(bal.outQty.rounded()),
                outValuePaise: bal.outValuePaise,
                closingQty: Int64(bal.onHandQty.rounded()),
                closingValuePaise: bal.onHandValuePaise,
                averageCostPaise: avg
            ))
        }
        return ReportResult.StockValuationReport(asOfDate: asOfDate, rows: rows)
    }
}
