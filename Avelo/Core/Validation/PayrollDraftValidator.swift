import Foundation

public struct PayrollDraftValidator: Sendable {

    public struct Input: Sendable {
        public var employeeId: PayrollEmployee.ID
        public var month: Int
        public var year: Int
        public var grossPaise: Int64
        public var deductionsPaise: Int64
        public var netPaise: Int64
        public var employeeActive: Bool
        public var employeeHasEndDate: Bool

        public init(employeeId: PayrollEmployee.ID,
                    month: Int,
                    year: Int,
                    grossPaise: Int64,
                    deductionsPaise: Int64,
                    netPaise: Int64,
                    employeeActive: Bool,
                    employeeHasEndDate: Bool) {
            self.employeeId = employeeId
            self.month = month
            self.year = year
            self.grossPaise = grossPaise
            self.deductionsPaise = deductionsPaise
            self.netPaise = netPaise
            self.employeeActive = employeeActive
            self.employeeHasEndDate = employeeHasEndDate
        }
    }

    public init() {}

    public func validate(_ input: Input) -> ValidationResult {
        var errors: [ValidationError] = []

        if !(1...12).contains(input.month) {
            errors.append(ValidationError(
                code: .financialYearZeroLength,
                field: "month",
                message: "Month must be between 1 and 12."
            ))
        }
        if !(2000...9999).contains(input.year) {
            errors.append(ValidationError(
                code: .financialYearZeroLength,
                field: "year",
                message: "Year must be between 2000 and 9999."
            ))
        }

        if input.grossPaise <= 0 {
            errors.append(ValidationError(
                code: .payrollNetMismatch,
                field: "gross",
                message: "Gross salary must be greater than zero."
            ))
        }

        if input.deductionsPaise < 0 {
            errors.append(ValidationError(
                code: .payrollNetMismatch,
                field: "deductions",
                message: "Deductions cannot be negative."
            ))
        }

        do {
            let expectedNet = try CheckedMath.subtract(
                input.grossPaise,
                input.deductionsPaise,
                context: "calculating payroll net salary"
            )
            if input.netPaise != expectedNet {
                errors.append(ValidationError(
                    code: .payrollNetMismatch,
                    field: "net",
                    message: "Net salary does not equal gross minus deductions."
                ))
            }
        } catch {
            errors.append(ValidationError(
                code: .arithmeticOverflow,
                field: "net",
                message: "Payroll net salary overflowed Int64 while validating gross minus deductions."
            ))
        }

        if input.employeeHasEndDate || !input.employeeActive {
            errors.append(ValidationError(
                code: .payrollEmployeeTerminated,
                field: "employee",
                message: "Employee is not active."
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
