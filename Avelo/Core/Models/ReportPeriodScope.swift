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
