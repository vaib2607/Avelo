import Foundation

/// Compiled whitelist of workspaces that may persist configuration. Raw
/// values are the stable identifiers stored in
/// `avelo_workspace_configurations.workspace_id`; never rename a case's raw
/// value once shipped.
public enum WorkspaceIdentifier: String, CaseIterable, Sendable, Codable {
    case dashboard
    case accounts
    case vouchers
    case reports
    case inventory
    case gst
    case payroll
    case banking
    case audit
}

/// Versioned, per-company, per-workspace presentation settings (the
/// F12-equivalent). Persisted as JSON in `avelo_workspace_configurations`.
///
/// Hard rule (master plan / Avelo_Rules): only validated stable identifiers
/// and presentation metadata may be persisted — never financial totals,
/// account balances, or SQL fragments. Filters store field identifiers and
/// literal values; the query they influence is always built by typed report
/// services.
public struct WorkspaceConfiguration: Codable, Hashable, Sendable {
    /// Bump when the payload shape changes incompatibly; the repository
    /// discards payloads with a newer version than it understands.
    public static let currentFormatVersion = 1

    public enum Density: String, Codable, CaseIterable, Sendable {
        case compact
        case comfortable
    }

    public enum GridBehavior: String, Codable, CaseIterable, Sendable {
        case plain
        case alternatingRows
        case ruled
    }

    public enum FocusBehavior: String, Codable, CaseIterable, Sendable {
        case rememberLastRow
        case firstRow
    }

    public enum ComparisonPeriod: String, Codable, CaseIterable, Sendable {
        case none
        case previousPeriod
        case previousFinancialYear
    }

    public struct ColumnConfiguration: Codable, Hashable, Sendable {
        public let fieldId: String
        public var isVisible: Bool
        public var width: Double?

        public init(fieldId: String, isVisible: Bool = true, width: Double? = nil) {
            self.fieldId = fieldId
            self.isVisible = isVisible
            self.width = width
        }
    }

    /// A saved filter: a field identifier, a closed operator set, and a
    /// literal value. Deliberately not an expression language.
    public struct FilterRule: Codable, Hashable, Sendable {
        public enum Operator: String, Codable, CaseIterable, Sendable {
            case equals
            case contains
            case greaterThan
            case lessThan
        }

        public let fieldId: String
        public let op: Operator
        public let value: String

        public init(fieldId: String, op: Operator, value: String) {
            self.fieldId = fieldId
            self.op = op
            self.value = value
        }
    }

    public struct PrintDefaults: Codable, Hashable, Sendable {
        public var pageSizeId: String
        public var isLandscape: Bool

        public init(pageSizeId: String = "a4", isLandscape: Bool = false) {
            self.pageSizeId = pageSizeId
            self.isLandscape = isLandscape
        }
    }

    public struct ExportDefaults: Codable, Hashable, Sendable {
        public enum Format: String, Codable, CaseIterable, Sendable {
            case csv
            case pdf
        }

        public var format: Format

        public init(format: Format = .csv) {
            self.format = format
        }
    }

    public var formatVersion: Int
    public var density: Density
    public var showsFieldLabels: Bool
    public var columns: [ColumnConfiguration]
    public var gridBehavior: GridBehavior
    public var filters: [FilterRule]
    public var groupingFieldIds: [String]
    public var comparison: ComparisonPeriod
    public var focusBehavior: FocusBehavior
    public var printDefaults: PrintDefaults
    public var exportDefaults: ExportDefaults

    public init(formatVersion: Int = WorkspaceConfiguration.currentFormatVersion,
                density: Density = .comfortable,
                showsFieldLabels: Bool = true,
                columns: [ColumnConfiguration] = [],
                gridBehavior: GridBehavior = .plain,
                filters: [FilterRule] = [],
                groupingFieldIds: [String] = [],
                comparison: ComparisonPeriod = .none,
                focusBehavior: FocusBehavior = .rememberLastRow,
                printDefaults: PrintDefaults = PrintDefaults(),
                exportDefaults: ExportDefaults = ExportDefaults()) {
        self.formatVersion = formatVersion
        self.density = density
        self.showsFieldLabels = showsFieldLabels
        self.columns = columns
        self.gridBehavior = gridBehavior
        self.filters = filters
        self.groupingFieldIds = groupingFieldIds
        self.comparison = comparison
        self.focusBehavior = focusBehavior
        self.printDefaults = printDefaults
        self.exportDefaults = exportDefaults
    }

    /// True when every persisted identifier is a plausible stable identifier
    /// (short, no whitespace/quotes/SQL punctuation). Enforced at the
    /// repository boundary on both save and load.
    public var hasValidIdentifiers: Bool {
        let ids = columns.map(\.fieldId)
            + filters.map(\.fieldId)
            + groupingFieldIds
            + [printDefaults.pageSizeId]
        return ids.allSatisfy(Self.isValidIdentifier)
    }

    public static func isValidIdentifier(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }
    }
}
