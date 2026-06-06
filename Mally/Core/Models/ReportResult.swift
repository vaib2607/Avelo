import Foundation

public enum ReportResult {

    public struct ReportFilter: Hashable, Sendable {
        public var companyId: Company.ID
        public var financialYearId: FinancialYear.ID?
        public var fromDate: Date?
        public var toDate: Date?
        public var accountId: Account.ID?
        public var voucherTypeCodes: Set<VoucherType.Code>
        public var includeOpening: Bool

        public init(companyId: Company.ID,
                    financialYearId: FinancialYear.ID? = nil,
                    fromDate: Date? = nil,
                    toDate: Date? = nil,
                    accountId: Account.ID? = nil,
                    voucherTypeCodes: Set<VoucherType.Code> = [],
                    includeOpening: Bool = true) {
            self.companyId = companyId
            self.financialYearId = financialYearId
            self.fromDate = fromDate
            self.toDate = toDate
            self.accountId = accountId
            self.voucherTypeCodes = voucherTypeCodes
            self.includeOpening = includeOpening
        }
    }

    public enum Section: String, CaseIterable, Sendable, Codable {
        case assets
        case liabilities
        case income
        case expense

        public var displayName: String {
            switch self {
            case .assets:      return "Assets"
            case .liabilities: return "Liabilities"
            case .income:      return "Income"
            case .expense:     return "Expense"
            }
        }
    }

    public struct LedgerRow: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let date: Date
        public let voucherNumber: String
        public let voucherTypeCode: VoucherType.Code
        public let narration: String
        public let debitPaise: Int64
        public let creditPaise: Int64
        public let balancePaise: Int64
        public let voucherId: Voucher.ID

        public init(id: UUID = UUID(),
                    date: Date,
                    voucherNumber: String,
                    voucherTypeCode: VoucherType.Code,
                    narration: String,
                    debitPaise: Int64,
                    creditPaise: Int64,
                    balancePaise: Int64,
                    voucherId: Voucher.ID) {
            self.id = id
            self.date = date
            self.voucherNumber = voucherNumber
            self.voucherTypeCode = voucherTypeCode
            self.narration = narration
            self.debitPaise = debitPaise
            self.creditPaise = creditPaise
            self.balancePaise = balancePaise
            self.voucherId = voucherId
        }
    }

    public struct LedgerReport: Sendable, Hashable {
        public let accountId: Account.ID
        public let accountName: String
        public let openingBalancePaise: Int64
        public let rows: [LedgerRow]
        public let closingBalancePaise: Int64
    }

    public struct TrialBalanceRow: Identifiable, Hashable, Sendable {
        public let id: Account.ID
        public let accountCode: String
        public let accountName: String
        public let groupPath: String
        public let debitPaise: Int64
        public let creditPaise: Int64

        public init(id: Account.ID, accountCode: String, accountName: String, groupPath: String, debitPaise: Int64, creditPaise: Int64) {
            self.id = id
            self.accountCode = accountCode
            self.accountName = accountName
            self.groupPath = groupPath
            self.debitPaise = debitPaise
            self.creditPaise = creditPaise
        }
    }

    public struct TrialBalance: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [TrialBalanceRow]
        public let totalDebitPaise: Int64
        public let totalCreditPaise: Int64
    }

    public struct ProfitLossSection: Sendable, Hashable {
        public let title: String
        public let rows: [TrialBalanceRow]
        public let totalPaise: Int64
    }

    public struct ProfitLoss: Sendable, Hashable {
        public let fromDate: Date
        public let toDate: Date
        public let directIncome: ProfitLossSection
        public let indirectIncome: ProfitLossSection
        public let directExpense: ProfitLossSection
        public let indirectExpense: ProfitLossSection
        public let totalIncomePaise: Int64
        public let totalExpensePaise: Int64
        public let netProfitPaise: Int64
    }

    public struct BalanceSheetSection: Sendable, Hashable {
        public let title: String
        public let rows: [TrialBalanceRow]
        public let totalPaise: Int64
    }

    public struct BalanceSheet: Sendable, Hashable {
        public let asOfDate: Date
        public let liabilities: [BalanceSheetSection]
        public let assets: [BalanceSheetSection]
        public let totalLiabilitiesPaise: Int64
        public let totalAssetsPaise: Int64
        public let balancingEquityPaise: Int64
    }

    public struct GstBucket: Hashable, Sendable {
        public let label: String
        public let amountPaise: Int64
    }

    public struct GstSummary: Sendable, Hashable {
        public let fromDate: Date
        public let toDate: Date
        public let output: [GstBucket]
        public let input: [GstBucket]
        public let netPayablePaise: Int64
    }

    public struct DayBookRow: Identifiable, Hashable, Sendable {
        public let id: Voucher.ID
        public let timestamp: Date
        public let voucherNumber: String
        public let voucherTypeCode: VoucherType.Code
        public let partyName: String
        public let narration: String
        public let totalDebitPaise: Int64
        public let totalCreditPaise: Int64

        public init(id: Voucher.ID,
                    timestamp: Date,
                    voucherNumber: String,
                    voucherTypeCode: VoucherType.Code,
                    partyName: String,
                    narration: String,
                    totalDebitPaise: Int64,
                    totalCreditPaise: Int64) {
            self.id = id
            self.timestamp = timestamp
            self.voucherNumber = voucherNumber
            self.voucherTypeCode = voucherTypeCode
            self.partyName = partyName
            self.narration = narration
            self.totalDebitPaise = totalDebitPaise
            self.totalCreditPaise = totalCreditPaise
        }
    }

    public struct OutstandingRow: Identifiable, Hashable, Sendable {
        public let id: Account.ID
        public let accountName: String
        public let totalPaise: Int64
        public let age0to30Paise: Int64
        public let age31to60Paise: Int64
        public let age61to90Paise: Int64
        public let age90PlusPaise: Int64
    }

    public struct OutstandingReport: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [OutstandingRow]
        public let direction: Direction

        public enum Direction: String, Sendable, CaseIterable {
            case receivables
            case payables
            case both
        }
    }

    public struct StockValuationRow: Identifiable, Hashable, Sendable {
        public let id: InventoryItem.ID
        public let itemCode: String
        public let itemName: String
        public let unit: String
        public let openingQty: Int64
        public let openingValuePaise: Int64
        public let inQty: Int64
        public let inValuePaise: Int64
        public let outQty: Int64
        public let outValuePaise: Int64
        public let closingQty: Int64
        public let closingValuePaise: Int64
        public let averageCostPaise: Int64
    }

    public struct StockValuationReport: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [StockValuationRow]
    }
}
