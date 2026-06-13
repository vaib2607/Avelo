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
                               bankAccount: String?,
                               ifsc: String?,
                               basicPaise: Int64,
                               hraPaise: Int64,
                               otherAllowancesPaise: Int64,
                               pfApplicable: Bool,
                               esiApplicable: Bool) throws -> PayrollEmployee {
        let employee = PayrollEmployee(
            companyId: companyId,
            employeeCode: employeeCode,
            name: name,
            designation: designation,
            pan: pan,
            bankAccount: bankAccount,
            ifsc: ifsc,
            basicPaise: basicPaise,
            hraPaise: hraPaise,
            otherAllowancesPaise: otherAllowancesPaise,
            pfApplicable: pfApplicable,
            esiApplicable: esiApplicable,
            isActive: true,
            joinedOn: Date()
        )
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            try repo.insertEmployee(employee)
            try AuditService(db: tx, companyId: companyId).record(
                action: .employeeCreated,
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
                action: .employeeUpdated,
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
                action: .employeeDeactivated,
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
                          workingDays: Int,
                          paidDays: Int,
                          overtimePaise: Int64,
                          deductionsPaise: Int64,
                          financialYearId: FinancialYear.ID) throws -> PayrollEntry {
        let employee = try repository.findEmployee(id: employeeId)
        guard let employee = employee else { throw AppError.notFound("Employee") }

        let gross = employee.basicPaise + employee.hraPaise + employee.otherAllowancesPaise + overtimePaise
        let net = gross - deductionsPaise
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
        let entry = PayrollEntry(
            id: UUID(),
            companyId: companyId,
            employeeId: employeeId,
            financialYearId: financialYearId,
            month: month,
            year: year,
            grossPaise: gross,
            deductionsPaise: deductionsPaise,
            netPaise: net,
            workingDays: Double(workingDays),
            paidDays: Double(paidDays),
            basicPaise: employee.basicPaise,
            hraPaise: employee.hraPaise,
            otherAllowancesPaise: employee.otherAllowancesPaise,
            overtimePaise: overtimePaise,
            pfApplicable: employee.pfApplicable,
            esiApplicable: employee.esiApplicable,
            postedAt: Date()
        )
        try db.write { tx in
            let repo = PayrollRepository(db: tx)
            let existing = try repo.listEntries(filter: .init(companyId: companyId, employeeId: employeeId, financialYearId: financialYearId, monthYear: (year, month), limit: 1))
            if !existing.isEmpty {
                throw AppError.duplicateSalary("Payroll already posted for this employee and month.")
            }
            try repo.insertEntry(entry)
            try AuditService(db: tx, companyId: companyId).record(
                action: .payrollEntryPosted,
                entityType: "payroll_entry",
                entityId: entry.id.uuidString,
                snapshotAfter: entry
            )
        }
        return entry
    }
}
