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
        public let entries: [LedgerRow]
        public let closingBalancePaise: Int64
        public let periodDebitPaise: Int64
        public let periodCreditPaise: Int64

        public init(accountId: Account.ID,
                    accountName: String,
                    openingBalancePaise: Int64,
                    rows: [LedgerRow],
                    closingBalancePaise: Int64,
                    periodDebitPaise: Int64 = 0,
                    periodCreditPaise: Int64 = 0) {
            self.accountId = accountId
            self.accountName = accountName
            self.openingBalancePaise = openingBalancePaise
            self.rows = rows
            self.entries = rows
            self.closingBalancePaise = closingBalancePaise
            self.periodDebitPaise = periodDebitPaise
            self.periodCreditPaise = periodCreditPaise
        }
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

    public struct ProfitLossSection: Sendable, Hashable, RandomAccessCollection {
        public let title: String
        public let rows: [TrialBalanceRow]
        public let totalPaise: Int64

        public init(title: String, rows: [TrialBalanceRow], totalPaise: Int64) {
            self.title = title
            self.rows = rows
            self.totalPaise = totalPaise
        }

        public var startIndex: Int { rows.startIndex }
        public var endIndex: Int { rows.endIndex }
        public subscript(position: Int) -> TrialBalanceRow { rows[position] }
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

        public var totalExpensesPaise: Int64 { totalExpensePaise }
        public var income: ProfitLossSection { directIncome }
        public var expenses: ProfitLossSection { directExpense }
    }

    public struct BalanceSheetSection: Sendable, Hashable, Identifiable, RandomAccessCollection {
        public let id: String
        public let title: String
        public let rows: [TrialBalanceRow]
        public let totalPaise: Int64

        public init(id: String, title: String, rows: [TrialBalanceRow], totalPaise: Int64) {
            self.id = id
            self.title = title
            self.rows = rows
            self.totalPaise = totalPaise
        }

        public var startIndex: Int { rows.startIndex }
        public var endIndex: Int { rows.endIndex }
        public subscript(position: Int) -> TrialBalanceRow { rows[position] }
    }

    public struct BalanceSheet: Sendable, Hashable {
        public let asOfDate: Date
        public let liabilities: [BalanceSheetSection]
        public let assets: [BalanceSheetSection]
        public let equity: [BalanceSheetSection]
        public let totalLiabilitiesPaise: Int64
        public let totalAssetsPaise: Int64
        public let totalEquityPaise: Int64
        public let balancingEquityPaise: Int64

        public init(asOfDate: Date,
                    assets: [BalanceSheetSection],
                    liabilities: [BalanceSheetSection],
                    equity: [BalanceSheetSection],
                    totalAssetsPaise: Int64,
                    totalLiabilitiesPaise: Int64,
                    totalEquityPaise: Int64,
                    balancingEquityPaise: Int64) {
            self.asOfDate = asOfDate
            self.assets = assets
            self.liabilities = liabilities
            self.equity = equity
            self.totalAssetsPaise = totalAssetsPaise
            self.totalLiabilitiesPaise = totalLiabilitiesPaise
            self.totalEquityPaise = totalEquityPaise
            self.balancingEquityPaise = balancingEquityPaise
        }
    }

    public struct GstBucket: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let amountPaise: Int64

        public init(id: String, label: String, amountPaise: Int64) {
            self.id = id
            self.label = label
            self.amountPaise = amountPaise
        }
    }

    public struct GstSummary: Sendable, Hashable {
        public let fromDate: Date
        public let toDate: Date
        public let output: [GstBucket]
        public let input: [GstBucket]
        public let outputTaxablePaise: Int64
        public let inputTaxablePaise: Int64
        public let outputTaxPaise: Int64
        public let inputTaxPaise: Int64
        public let netPayablePaise: Int64

        public var igstPaise: Int64 { output.last(where: { $0.label.contains("IGST") })?.amountPaise ?? 0 }
        public var cgstPaise: Int64 { output.last(where: { $0.label.contains("CGST") })?.amountPaise ?? 0 }
        public var sgstPaise: Int64 { output.last(where: { $0.label.contains("SGST") })?.amountPaise ?? 0 }
        public var cessPaise: Int64 { output.last(where: { $0.label.contains("CESS") })?.amountPaise ?? 0 }

        public init(fromDate: Date,
                    toDate: Date,
                    output: [GstBucket],
                    input: [GstBucket],
                    outputTaxablePaise: Int64 = 0,
                    inputTaxablePaise: Int64 = 0,
                    outputTaxPaise: Int64 = 0,
                    inputTaxPaise: Int64 = 0,
                    netPayablePaise: Int64) {
            self.fromDate = fromDate
            self.toDate = toDate
            self.output = output
            self.input = input
            self.outputTaxablePaise = outputTaxablePaise
            self.inputTaxablePaise = inputTaxablePaise
            self.outputTaxPaise = outputTaxPaise
            self.inputTaxPaise = inputTaxPaise
            self.netPayablePaise = netPayablePaise
        }
    }

    public struct DayBookRow: Identifiable, Hashable, Sendable {
        public let id: Voucher.ID
        public let timestamp: Date
        public let date: Date
        public let voucherNumber: String
        public let number: String
        public let typeCode: String
        public let voucherTypeCode: VoucherType.Code
        public let partyName: String
        public let narration: String
        public let totalDebitPaise: Int64
        public let totalCreditPaise: Int64
        public let amountPaise: Int64

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
            self.date = timestamp
            self.voucherNumber = voucherNumber
            self.number = voucherNumber
            self.typeCode = voucherTypeCode.rawValue
            self.voucherTypeCode = voucherTypeCode
            self.partyName = partyName
            self.narration = narration
            self.totalDebitPaise = totalDebitPaise
            self.totalCreditPaise = totalCreditPaise
            self.amountPaise = totalDebitPaise
        }
    }

    public struct OutstandingRow: Identifiable, Hashable, Sendable {
        public let id: String
        public let accountId: Account.ID
        public let accountName: String
        public let partyName: String
        public let referenceNumber: String
        public let asOf: Date
        public let totalPaise: Int64
        public let amountPaise: Int64
        public let age0to30Paise: Int64
        public let age31to60Paise: Int64
        public let age61to90Paise: Int64
        public let age90PlusPaise: Int64
        public let ageInDays: Int

        public init(id: String,
                    accountId: Account.ID,
                    partyName: String,
                    referenceNumber: String,
                    asOf: Date,
                    amountPaise: Int64,
                    age0to30Paise: Int64 = 0,
                    age31to60Paise: Int64 = 0,
                    age61to90Paise: Int64 = 0,
                    age90PlusPaise: Int64 = 0,
                    ageInDays: Int = 0) {
            self.id = id
            self.accountId = accountId
            self.accountName = partyName
            self.partyName = partyName
            self.referenceNumber = referenceNumber
            self.asOf = asOf
            self.totalPaise = amountPaise
            self.amountPaise = amountPaise
            self.age0to30Paise = age0to30Paise
            self.age31to60Paise = age31to60Paise
            self.age61to90Paise = age61to90Paise
            self.age90PlusPaise = age90PlusPaise
            self.ageInDays = ageInDays
        }
    }

    public struct OutstandingReport: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [OutstandingRow]
        public let direction: Direction
        public let totalPaise: Int64

        public enum Direction: String, Sendable, CaseIterable {
            case receivable
            case receivables
            case payable
            case payables
            case both
        }
    }

    public struct StockValuationRow: Identifiable, Hashable, Sendable {
        public let id: InventoryItem.ID
        public let itemCode: String
        public let itemName: String
        public let unit: String
        public let quantity: ExactQuantity
        public let ratePaise: Int64
        public let valuePaise: Int64
        public let openingQty: ExactQuantity
        public let openingValuePaise: Int64
        public let inQty: ExactQuantity
        public let inValuePaise: Int64
        public let outQty: ExactQuantity
        public let outValuePaise: Int64
        public let closingQty: ExactQuantity
        public let closingValuePaise: Int64
        public let averageCostPaise: Int64
    }

    public struct StockValuationReport: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [StockValuationRow]
        public let totalPaise: Int64

        public init(asOfDate: Date, rows: [StockValuationRow], totalPaise: Int64 = 0) {
            self.asOfDate = asOfDate
            self.rows = rows
            self.totalPaise = totalPaise
        }
    }

    public struct CashFlowRow: Identifiable, Hashable, Sendable {
        public let id: String
        public let section: Section
        public let accountCode: String
        public let accountName: String
        public let inflowPaise: Int64
        public let outflowPaise: Int64
        public let netPaise: Int64

        public enum Section: String, CaseIterable, Sendable {
            case operating
            case investing
            case financing

            public var displayName: String {
                switch self {
                case .operating: return "Operating Activities"
                case .investing: return "Investing Activities"
                case .financing: return "Financing Activities"
                }
            }
        }
    }

    public struct CashFlowStatement: Sendable, Hashable {
        public let fromDate: Date
        public let toDate: Date
        public let rows: [CashFlowRow]
        public let operatingNetPaise: Int64
        public let investingNetPaise: Int64
        public let financingNetPaise: Int64
        public let netCashFlowPaise: Int64
    }

    public struct StockAgeingRow: Identifiable, Hashable, Sendable {
        public let id: InventoryItem.ID
        public let itemCode: String
        public let itemName: String
        public let unit: String
        public let onHandQty: Int64
        public let onHandValuePaise: Int64
        public let age0to30Qty: Int64
        public let age31to60Qty: Int64
        public let age61to90Qty: Int64
        public let age90PlusQty: Int64
    }

    public struct StockAgeingReport: Sendable, Hashable {
        public let asOfDate: Date
        public let rows: [StockAgeingRow]
    }
}
