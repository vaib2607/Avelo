import Foundation

public final class PayrollService: Sendable {

    public let db: SQLiteDatabase
    public let repository: PayrollRepository
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = PayrollRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public func listEmployees(activeOnly: Bool = true) throws -> [PayrollEmployee] {
        try repository.listEmployees(companyId: companyId, activeOnly: activeOnly)
    }

    public func findEmployee(_ id: PayrollEmployee.ID) throws -> PayrollEmployee? {
        try repository.findEmployee(id: id)
    }

    public func createEmployee(name: String,
                               employeeCode: String,
                               designation: String?,
                               pan: String?,
                               bankAccountId: Account.ID? = nil,
                               baseSalaryPaise: Int64) throws -> PayrollEmployee {
        let employee = PayrollEmployee(
            companyId: companyId,
            employeeCode: employeeCode,
            name: name,
            designation: designation,
            pan: pan,
            bankAccountId: bankAccountId,
            baseSalaryPaise: baseSalaryPaise,
            isActive: true,
            joinedOn: Date()
        )
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            try repo.insertEmployee(employee)
            try AuditService(db: tx, companyId: companyId).record(
                action: .payrollEmployeeCreated,
                entityType: "payroll_employee",
                entityId: employee.id.uuidString,
                snapshotAfter: employee
            )
        }
        return employee
    }

    public func updateEmployee(_ employee: PayrollEmployee) throws {
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            try repo.updateEmployee(employee)
            try AuditService(db: tx, companyId: companyId).record(
                action: .payrollEmployeeUpdated,
                entityType: "payroll_employee",
                entityId: employee.id.uuidString,
                snapshotAfter: employee
            )
        }
    }

    public func deactivateEmployee(_ id: PayrollEmployee.ID) throws {
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            try repo.deactivateEmployee(id)
            try AuditService(db: tx, companyId: companyId).record(
                action: .payrollEmployeeTerminated,
                entityType: "payroll_employee",
                entityId: id.uuidString
            )
        }
    }

    public func listEntries(employeeId: PayrollEmployee.ID? = nil,
                            monthYear: Int? = nil) throws -> [PayrollEntry] {
        let my: (year: Int, month: Int)? = monthYear.map { my in
            (year: my / 100, month: my % 100)
        }
        let filter = PayrollRepository.EntryFilter(
            companyId: companyId,
            employeeId: employeeId,
            monthYear: my
        )
        return try repository.listEntries(filter: filter)
    }

    public func postEntry(employeeId: PayrollEmployee.ID,
                          monthYear: Int,
                          deductionsPaise: Int64,
                          financialYearId: FinancialYear.ID,
                          salaryExpenseAccountId: Account.ID,
                          paymentAccountId: Account.ID) throws -> PayrollEntry {
        let employee = try repository.findEmployee(id: employeeId)
        guard let employee = employee else { throw AppError.notFound("Employee") }

        let gross = employee.baseSalaryPaise
        let net = try CheckedMath.subtract(
            gross,
            deductionsPaise,
            context: "calculating payroll net salary"
        )
        let year = monthYear / 100
        let month = monthYear % 100
        let result = PayrollDraftValidator().validate(PayrollDraftValidator.Input(
            employeeId: employeeId,
            month: month,
            year: year,
            grossPaise: gross,
            deductionsPaise: deductionsPaise,
            netPaise: net,
            employeeActive: employee.isActive,
            employeeHasEndDate: employee.endDate != nil
        ))
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        try FiscalLockChecker(db: db).assertOpen(financialYearId: financialYearId)
        guard let expenseAccount = try AccountRepository(db: db).findById(salaryExpenseAccountId),
              expenseAccount.companyId == companyId,
              expenseAccount.isActive else {
            throw AppError.notFound("Salary expense account")
        }
        guard let paymentAccount = try AccountRepository(db: db).findById(paymentAccountId),
              paymentAccount.companyId == companyId,
              paymentAccount.isActive else {
            throw AppError.notFound("Payroll payment account")
        }
        let voucherDate = try salaryVoucherDate(month: month, year: year, financialYearId: financialYearId)
        let voucherId = UUID()
        let now = Date()
        let entry = PayrollEntry(
            id: UUID(),
            companyId: companyId,
            employeeId: employeeId,
            financialYearId: financialYearId,
            voucherId: voucherId,
            month: month,
            year: year,
            grossPaise: gross,
            deductionsPaise: deductionsPaise,
            netPaise: net,
            postedAt: Date()
        )
        var voucher: Voucher?
        let lines = [
            LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: salaryExpenseAccountId,
                amountPaise: gross,
                side: .debit,
                lineOrder: 0
            ),
            LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: paymentAccountId,
                amountPaise: gross,
                side: .credit,
                lineOrder: 1
            )
        ]
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            let existing = try repo.listEntries(filter: .init(companyId: companyId, employeeId: employeeId, financialYearId: financialYearId, monthYear: (year, month), limit: 1))
            if !existing.isEmpty {
                throw AppError.duplicateSalary("Payroll already posted for this employee and month.")
            }
            let number = try VoucherSequenceRepository(db: tx).nextNumber(
                companyId: companyId,
                financialYearId: financialYearId,
                typeCode: .payroll
            )
            let payrollVoucher = Voucher(
                id: voucherId,
                companyId: companyId,
                financialYearId: financialYearId,
                voucherTypeCode: .payroll,
                number: number,
                date: voucherDate,
                partyAccountId: paymentAccountId,
                narration: "Salary \(String(format: "%04d-%02d", year, month)) - \(employee.name)",
                isReversal: false,
                reversalOfId: nil,
                isPosted: true,
                totalPaise: gross,
                createdAt: now,
                updatedAt: now
            )
            try VoucherRepository(db: tx).insert(payrollVoucher)
            for line in lines {
                try tx.execute(
                    """
                    INSERT INTO avelo_ledger_lines
                    (id, company_id, voucher_id, account_id, amount_paise, side, tax_code, cost_center, line_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(line.id.uuidString),
                        .text(line.companyId.uuidString),
                        .text(line.voucherId.uuidString),
                        .text(line.accountId.uuidString),
                        .integer(line.amountPaise),
                        .text(line.side.rawValue),
                        .optionalText(line.taxCode),
                        .optionalText(line.costCenter),
                        .integer(Int64(line.lineOrder))
                    ]
                )
            }
            try repo.insertEntry(entry)
            try AuditService(db: tx, companyId: companyId).record(
                action: .salaryPosted,
                entityType: "payroll_entry",
                entityId: entry.id.uuidString,
                snapshotAfter: PayrollPostSnapshot(entry: entry, voucher: payrollVoucher, lines: lines)
            )
            voucher = payrollVoucher
        }
        guard voucher != nil else {
            throw AppError.validation(.init(code: .internal, message: "Payroll posting did not produce a voucher."))
        }
        ReportService.invalidateCache(companyId: companyId)
        return entry
    }

    private struct PayrollPostSnapshot: Sendable, Codable {
        let entry: PayrollEntry
        let voucher: Voucher
        let lines: [LedgerLine]
    }

    private func salaryVoucherDate(month: Int, year: Int, financialYearId: FinancialYear.ID) throws -> Date {
        guard let fy = try FinancialYearRepository(db: db).findById(financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        guard let monthStart = DateFormatters.parseDate(String(format: "%04d-%02d-01", year, month)) else {
            throw AppError.businessRule("Invalid salary month.")
        }
        guard monthStart >= fy.startDate && monthStart <= fy.endDate else {
            throw AppError.validation(.init(code: .voucherDateOutsideFY, message: "Salary month is outside the selected financial year."))
        }
        return monthStart
    }
}
