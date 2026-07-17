import Foundation

public struct ReportRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    struct MovementTotals: Sendable {
        let debitPaise: Int64
        let creditPaise: Int64
    }

    struct FinancialYearOpeningContext: Sendable {
        let financialYear: FinancialYear
        let signedOpeningByAccount: [Account.ID: Int64]
    }

    func movementTotals(
        for accountIds: [Account.ID],
        companyId: Company.ID,
        fromDate: Date? = nil,
        toDate: Date? = nil,
        financialYearId: FinancialYear.ID? = nil,
        voucherTypeCodes: Set<VoucherType.Code> = []
    ) throws -> [Account.ID: MovementTotals] {
        guard !accountIds.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: accountIds.count).joined(separator: ",")
        var sql = """
            SELECT l.account_id AS aid,
                   COALESCE(SUM(CASE WHEN l.side='debit' THEN l.amount_paise ELSE 0 END), 0) AS dr,
                   COALESCE(SUM(CASE WHEN l.side='credit' THEN l.amount_paise ELSE 0 END), 0) AS cr
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id AND v.company_id = l.company_id
            WHERE l.company_id = ? AND l.account_id IN (\(placeholders))
              AND v.is_posted = 1
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
        if let financialYearId {
            sql += " AND v.financial_year_id = ?"
            bind.append(.text(financialYearId.uuidString))
        }
        if !voucherTypeCodes.isEmpty {
            let placeholders = Array(repeating: "?", count: voucherTypeCodes.count).joined(separator: ",")
            sql += " AND v.voucher_type_code IN (\(placeholders))"
            bind.append(contentsOf: voucherTypeCodes.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) })
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
        let openingContext = try financialYearOpeningContext(filter: filter)
        let signedOpening: Int64 = try signedOpeningBalance(
            for: account,
            filter: filter,
            openingContext: openingContext
        )

        var sql = """
            SELECT v.id AS vid, v.date AS vdate, v.number AS vnum, v.voucher_type_code AS vtype,
                   v.narration AS vnarration, l.amount_paise AS amt, l.side AS lside, l.line_order AS ord
            FROM avelo_ledger_lines l
            JOIN avelo_vouchers v ON v.id = l.voucher_id AND v.company_id = l.company_id
            WHERE l.company_id = ? AND l.account_id = ?
              AND v.is_posted = 1
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
        if !filter.voucherTypeCodes.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.voucherTypeCodes.count).joined(separator: ",")
            sql += " AND v.voucher_type_code IN (\(placeholders))"
            bind.append(contentsOf: filter.voucherTypeCodes.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) })
        }
        sql += " ORDER BY v.date ASC, v.created_at ASC, l.line_order ASC"

        let rawRows: [(Voucher.ID, Date, String, VoucherType.Code, String, Int64, EntrySide, Int)] = try db.query(sql, bind: bind) { r in
            (
                try UUIDParsing.required(r.requiredText("vid"), field: "report.ledger.voucher_id"),
                try r.requiredDate("vdate"),
                try r.requiredText("vnum"),
                try r.enumValue("vtype"),
                try r.requiredText("vnarration"),
                try r.requiredInt("amt"),
                try r.enumValue("lside"),
                Int(try r.requiredInt("ord"))
            )
        }

        var running = signedOpening
        var periodDebitPaise: Int64 = 0
        var periodCreditPaise: Int64 = 0
        var rows: [ReportResult.LedgerRow] = []
        for (vid, date, num, type, narr, amt, side, _) in rawRows {
            if side == .debit {
                running = try CheckedMath.add(running, amt, context: "calculating ledger running balance")
                periodDebitPaise = try CheckedMath.add(periodDebitPaise, amt, context: "summing ledger period debit")
            } else {
                running = try CheckedMath.subtract(running, amt, context: "calculating ledger running balance")
                periodCreditPaise = try CheckedMath.add(periodCreditPaise, amt, context: "summing ledger period credit")
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
            closingBalancePaise: running,
            periodDebitPaise: periodDebitPaise,
            periodCreditPaise: periodCreditPaise
        )
    }

    // MARK: - Trial Balance

    public func trialBalance(asOfDate: Date, filter: ReportResult.ReportFilter) throws -> ReportResult.TrialBalance {
        let openingContext = try financialYearOpeningContext(filter: filter)
        let movementFromDate = openingContext?.financialYear.startDate
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
            fromDate: movementFromDate,
            toDate: asOfDate,
            financialYearId: filter.financialYearId
        )

        var rows: [ReportResult.TrialBalanceRow] = []
        var totalDr: Int64 = 0
        var totalCr: Int64 = 0
        for raw in raws {
            let movement = totalsByAccount[raw.id]
            let moveDr = movement?.debitPaise ?? 0
            let moveCr = movement?.creditPaise ?? 0
            let signedOpening: Int64 = openingContext?.signedOpeningByAccount[raw.id]
                ?? (raw.obs == "debit" ? raw.ob : -raw.ob)
            let openingDebit = signedOpening > 0 ? signedOpening : 0
            let openingCredit = signedOpening < 0 ? try CheckedMath.abs(signedOpening, context: "calculating trial balance opening credit") : 0
            let grossDebit = try CheckedMath.add(openingDebit, moveDr, context: "calculating trial balance gross debit")
            let grossCredit = try CheckedMath.add(openingCredit, moveCr, context: "calculating trial balance gross credit")
            let netDelta = try CheckedMath.subtract(grossDebit, grossCredit, context: "netting trial balance row")
            let netDebit = netDelta > 0 ? netDelta : 0
            let netCredit = netDelta < 0 ? try CheckedMath.abs(netDelta, context: "calculating trial balance net credit") : 0
            let groupPath = groupPathText(for: raw.gcode, groups: groupById)
            rows.append(ReportResult.TrialBalanceRow(
                id: raw.id,
                accountCode: raw.code,
                accountName: raw.name,
                groupPath: groupPath,
                debitPaise: netDebit,
                creditPaise: netCredit
            ))
            totalDr = try CheckedMath.add(totalDr, netDebit, context: "summing trial balance debit total")
            totalCr = try CheckedMath.add(totalCr, netCredit, context: "summing trial balance credit total")
        }
        return ReportResult.TrialBalance(
            asOfDate: asOfDate,
            rows: rows,
            totalDebitPaise: totalDr,
            totalCreditPaise: totalCr
        )
    }

    func financialYearOpeningContext(filter: ReportResult.ReportFilter) throws -> FinancialYearOpeningContext? {
        guard let financialYearId = filter.financialYearId,
              let financialYear = try FinancialYearRepository(db: db).findById(financialYearId) else {
            return nil
        }
        let rows = try FinancialYearOpeningBalanceRepository(db: db).listForFinancialYear(financialYearId)
        guard !rows.isEmpty else {
            return FinancialYearOpeningContext(financialYear: financialYear, signedOpeningByAccount: [:])
        }
        let signed = try Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.accountId, try row.signedOpeningBalancePaise())
        })
        return FinancialYearOpeningContext(financialYear: financialYear, signedOpeningByAccount: signed)
    }

    func signedOpeningBalance(for account: Account?,
                              filter: ReportResult.ReportFilter,
                              openingContext: FinancialYearOpeningContext?) throws -> Int64 {
        guard let account else { return 0 }
        if let carried = openingContext?.signedOpeningByAccount[account.id] {
            return carried
        }
        if let financialYear = openingContext?.financialYear {
            let priorMovements = try movementTotals(
                for: [account.id],
                companyId: filter.companyId,
                toDate: DateFormatters.utcCalendar.date(byAdding: .day, value: -1, to: financialYear.startDate),
                financialYearId: nil
            )[account.id]
            return try CheckedMath.subtract(
                try CheckedMath.add(
                    try account.signedOpeningBalancePaise(),
                    priorMovements?.debitPaise ?? 0,
                    context: "calculating fallback financial year opening debit"
                ),
                priorMovements?.creditPaise ?? 0,
                context: "calculating fallback financial year opening balance"
            )
        }
        return try account.signedOpeningBalancePaise()
    }

    private func groupPathText(for groupCode: String, groups: [AccountGroup.ID: AccountGroup]) -> String {
        _ = groups
        return groupCode
    }

}
