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
    public var basicPaise: Int64
    public var hraPaise: Int64
    public var otherAllowancesPaise: Int64
    public var bankAccount: String?
    public var ifsc: String?
    public var pfApplicable: Bool
    public var esiApplicable: Bool
    public var isActive: Bool
    public var joinedOn: Date
    public var endDate: Date?
    public let createdAt: Date

    public var employeeCode: String { code }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                employeeCode: String,
                name: String,
                designation: String? = nil,
                pan: String? = nil,
                bankAccount: String? = nil,
                ifsc: String? = nil,
                bankAccountId: Account.ID? = nil,
                basicPaise: Int64,
                hraPaise: Int64 = 0,
                otherAllowancesPaise: Int64 = 0,
                pfApplicable: Bool = true,
                esiApplicable: Bool = false,
                isActive: Bool = true,
                joinedOn: Date = Date(),
                endDate: Date? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.code = employeeCode
        self.name = name
        self.designation = designation
        self.pan = pan
        self.bankAccountId = bankAccountId
        self.baseSalaryPaise = basicPaise
        self.basicPaise = basicPaise
        self.hraPaise = hraPaise
        self.otherAllowancesPaise = otherAllowancesPaise
        self.bankAccount = bankAccount
        self.ifsc = ifsc
        self.pfApplicable = pfApplicable
        self.esiApplicable = esiApplicable
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
    public var workingDays: Double
    public var paidDays: Double
    public var basicPaise: Int64
    public var hraPaise: Int64
    public var otherAllowancesPaise: Int64
    public var overtimePaise: Int64
    public var pfApplicable: Bool
    public var esiApplicable: Bool
    public var employeeCode: String
    public var employeeName: String
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
                workingDays: Double = 0,
                paidDays: Double = 0,
                basicPaise: Int64 = 0,
                hraPaise: Int64 = 0,
                otherAllowancesPaise: Int64 = 0,
                overtimePaise: Int64 = 0,
                pfApplicable: Bool = true,
                esiApplicable: Bool = false,
                employeeCode: String = "",
                employeeName: String = "",
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
        self.workingDays = workingDays
        self.paidDays = paidDays
        self.basicPaise = basicPaise
        self.hraPaise = hraPaise
        self.otherAllowancesPaise = otherAllowancesPaise
        self.overtimePaise = overtimePaise
        self.pfApplicable = pfApplicable
        self.esiApplicable = esiApplicable
        self.employeeCode = employeeCode
        self.employeeName = employeeName
        self.postedAt = postedAt
    }

    public var monthYear: Int { year * 100 + month }
}
