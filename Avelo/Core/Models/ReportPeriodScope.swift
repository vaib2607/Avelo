import Foundation

/// Immutable period identity for report loading, reconciliation, and drill-down.
/// Validation belongs to `ReportService`; this value only preserves user intent.
public struct ReportPeriodScope: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case asOf(Date)
        case range(from: Date, to: Date)
    }

    public let companyId: Company.ID
    public let financialYearId: FinancialYear.ID?
    public let kind: Kind

    public init(companyId: Company.ID,
                financialYearId: FinancialYear.ID?,
                kind: Kind) {
        self.companyId = companyId
        self.financialYearId = financialYearId
        self.kind = kind
    }
}

/// Immutable, validated input for a Balance Sheet candidate. The explicit
/// values prevent verification/reconciliation from consulting ambient UI FY
/// state while a report is being constructed.
public struct BalanceSheetScope: Hashable, Sendable {
    public enum CanonicalReadMode: String, Hashable, Sendable {
        case compatibilityAdapters
    }

    public let companyId: Company.ID
    public let financialYearId: FinancialYear.ID
    public let financialYearStartDate: Date
    public let asOfDate: Date
    public let canonicalReadMode: CanonicalReadMode

    public init(companyId: Company.ID,
                financialYearId: FinancialYear.ID,
                financialYearStartDate: Date,
                asOfDate: Date,
                canonicalReadMode: CanonicalReadMode = .compatibilityAdapters) {
        self.companyId = companyId
        self.financialYearId = financialYearId
        self.financialYearStartDate = financialYearStartDate
        self.asOfDate = asOfDate
        self.canonicalReadMode = canonicalReadMode
    }
}
