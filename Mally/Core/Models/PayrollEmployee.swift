import Foundation

public struct PayrollEmployee: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var code: String
    public var name: String
    public var designation: String?
    public var pan: String?
    public var bankAccountId: Account.ID?
    public var baseSalaryPaise: Int64
    public var isActive: Bool
    public var joinedOn: Date
    public var endDate: Date?
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                code: String,
                name: String,
                designation: String? = nil,
                pan: String? = nil,
                bankAccountId: Account.ID? = nil,
                baseSalaryPaise: Int64,
                isActive: Bool = true,
                joinedOn: Date,
                endDate: Date? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = code
        self.name = name
        self.designation = designation
        self.pan = pan
        self.bankAccountId = bankAccountId
        self.baseSalaryPaise = baseSalaryPaise
        self.isActive = isActive
        self.joinedOn = joinedOn
        self.endDate = endDate
        self.createdAt = createdAt
    }

    public func isEmployed(on date: Date) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)
        if day < cal.startOfDay(for: joinedOn) { return false }
        if let end = endDate, day > cal.startOfDay(for: end) { return false }
        return isActive
    }
}

public struct PayrollEntry: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var employeeId: PayrollEmployee.ID
    public var financialYearId: FinancialYear.ID
    public var voucherId: Voucher.ID?
    public var month: Int
    public var year: Int
    public var grossPaise: Int64
    public var deductionsPaise: Int64
    public var netPaise: Int64
    public let postedAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                employeeId: PayrollEmployee.ID,
                financialYearId: FinancialYear.ID,
                voucherId: Voucher.ID? = nil,
                month: Int,
                year: Int,
                grossPaise: Int64,
                deductionsPaise: Int64,
                netPaise: Int64,
                postedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.employeeId = employeeId
        self.financialYearId = financialYearId
        self.voucherId = voucherId
        self.month = month
        self.year = year
        self.grossPaise = grossPaise
        self.deductionsPaise = deductionsPaise
        self.netPaise = netPaise
        self.postedAt = postedAt
    }
}
