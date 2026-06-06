import Foundation

public struct PayrollRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func findEmployeeById(_ id: PayrollEmployee.ID) throws -> PayrollEmployee? {
        try db.queryOne(
            """
            SELECT id, company_id, code, name, designation, pan, bank_account_id, base_salary_paise,
                   is_active, joined_on, end_date, created_at
            FROM mally_payroll_employees WHERE id = ?
            """,
            bind: [.text(id.uuidString)]
        ) { try Self.rowToEmployee($0) }
    }

    public func listEmployeesForCompany(_ companyId: Company.ID, includeInactive: Bool = false) throws -> [PayrollEmployee] {
        let sql = """
            SELECT id, company_id, code, name, designation, pan, bank_account_id, base_salary_paise,
                   is_active, joined_on, end_date, created_at
            FROM mally_payroll_employees
            WHERE company_id = ?\(includeInactive ? "" : " AND is_active = 1")
            ORDER BY code COLLATE NOCASE
        """
        return try db.query(sql, bind: [.text(companyId.uuidString)]) { try Self.rowToEmployee($0) }
    }

    public func insertEmployee(_ e: PayrollEmployee) throws {
        try db.execute(
            """
            INSERT INTO mally_payroll_employees
            (id, company_id, code, name, designation, pan, bank_account_id, base_salary_paise,
             is_active, joined_on, end_date, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(e.id.uuidString),
                .text(e.companyId.uuidString),
                .text(e.code),
                .text(e.name),
                .optionalText(e.designation),
                .optionalText(e.pan),
                .optionalText(e.bankAccountId?.uuidString),
                .integer(e.baseSalaryPaise),
                .bool(e.isActive),
                .date(e.joinedOn),
                .optionalDate(e.endDate),
                .timestamp(e.createdAt)
            ]
        )
    }

    public func updateEmployee(_ e: PayrollEmployee) throws {
        try db.execute(
            """
            UPDATE mally_payroll_employees SET
                code = ?, name = ?, designation = ?, pan = ?, bank_account_id = ?,
                base_salary_paise = ?, is_active = ?, joined_on = ?, end_date = ?
            WHERE id = ?
            """,
            [
                .text(e.code),
                .text(e.name),
                .optionalText(e.designation),
                .optionalText(e.pan),
                .optionalText(e.bankAccountId?.uuidString),
                .integer(e.baseSalaryPaise),
                .bool(e.isActive),
                .date(e.joinedOn),
                .optionalDate(e.endDate),
                .text(e.id.uuidString)
            ]
        )
    }

    public func terminateEmployee(_ id: PayrollEmployee.ID, endDate: Date) throws {
        try db.execute(
            "UPDATE mally_payroll_employees SET end_date = ?, is_active = 0 WHERE id = ?",
            [.date(endDate), .text(id.uuidString)]
        )
    }

    public func insertEntry(_ e: PayrollEntry) throws {
        try db.execute(
            """
            INSERT INTO mally_payroll_entries
            (id, company_id, employee_id, financial_year_id, voucher_id, month, year,
             gross_paise, deductions_paise, net_paise, posted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(e.id.uuidString),
                .text(e.companyId.uuidString),
                .text(e.employeeId.uuidString),
                .text(e.financialYearId.uuidString),
                .optionalText(e.voucherId?.uuidString),
                .integer(Int64(e.month)),
                .integer(Int64(e.year)),
                .integer(e.grossPaise),
                .integer(e.deductionsPaise),
                .integer(e.netPaise),
                .timestamp(e.postedAt)
            ]
        )
    }

    public struct EntryFilter: Sendable {
        public var companyId: Company.ID
        public var employeeId: PayrollEmployee.ID?
        public var financialYearId: FinancialYear.ID?
        public var year: Int?
        public var month: Int?
        public var limit: Int
        public var offset: Int

        public init(companyId: Company.ID,
                    employeeId: PayrollEmployee.ID? = nil,
                    financialYearId: FinancialYear.ID? = nil,
                    year: Int? = nil,
                    month: Int? = nil,
                    limit: Int = 200,
                    offset: Int = 0) {
            self.companyId = companyId
            self.employeeId = employeeId
            self.financialYearId = financialYearId
            self.year = year
            self.month = month
            self.limit = limit
            self.offset = offset
        }
    }

    public func listEntries(filter: EntryFilter) throws -> [PayrollEntry] {
        var sql = """
            SELECT id, company_id, employee_id, financial_year_id, voucher_id, month, year,
                   gross_paise, deductions_paise, net_paise, posted_at
            FROM mally_payroll_entries
            WHERE company_id = ?
        """
        var bind: [SQLValue] = [.text(filter.companyId.uuidString)]
        if let empId = filter.employeeId {
            sql += " AND employee_id = ?"
            bind.append(.text(empId.uuidString))
        }
        if let fyId = filter.financialYearId {
            sql += " AND financial_year_id = ?"
            bind.append(.text(fyId.uuidString))
        }
        if let y = filter.year {
            sql += " AND year = ?"
            bind.append(.integer(Int64(y)))
        }
        if let m = filter.month {
            sql += " AND month = ?"
            bind.append(.integer(Int64(m)))
        }
        sql += " ORDER BY year DESC, month DESC, posted_at DESC LIMIT ? OFFSET ?"
        bind.append(.integer(Int64(filter.limit)))
        bind.append(.integer(Int64(filter.offset)))
        return try db.query(sql, bind: bind) { try Self.rowToEntry($0) }
    }

    static func rowToEmployee(_ r: Row) throws -> PayrollEmployee {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let bank = r.optionalText("bank_account_id").flatMap { UUID(uuidString: $0) }
        return PayrollEmployee(
            id: id,
            companyId: companyId,
            code: r.text("code"),
            name: r.text("name"),
            designation: r.optionalText("designation"),
            pan: r.optionalText("pan"),
            bankAccountId: bank,
            baseSalaryPaise: r.int("base_salary_paise"),
            isActive: r.bool("is_active"),
            joinedOn: r.date("joined_on"),
            endDate: r.optionalText("end_date").flatMap { DateFormatters.parseDate($0) },
            createdAt: r.timestamp("created_at")
        )
    }

    static func rowToEntry(_ r: Row) throws -> PayrollEntry {
        let id = UUID(uuidString: r.text("id")) ?? UUID()
        let companyId = UUID(uuidString: r.text("company_id")) ?? UUID()
        let employeeId = UUID(uuidString: r.text("employee_id")) ?? UUID()
        let fyId = UUID(uuidString: r.text("financial_year_id")) ?? UUID()
        let voucherId = r.optionalText("voucher_id").flatMap { UUID(uuidString: $0) }
        return PayrollEntry(
            id: id,
            companyId: companyId,
            employeeId: employeeId,
            financialYearId: fyId,
            voucherId: voucherId,
            month: Int(r.int("month")),
            year: Int(r.int("year")),
            grossPaise: r.int("gross_paise"),
            deductionsPaise: r.int("deductions_paise"),
            netPaise: r.int("net_paise"),
            postedAt: r.timestamp("posted_at")
        )
    }
}
