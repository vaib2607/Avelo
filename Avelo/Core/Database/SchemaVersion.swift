import Foundation

public enum SchemaVersion: Int, CaseIterable, Sendable, Comparable {
    case v1 = 1
    case v2 = 2
    case v3 = 3
    case v4 = 4

    public static let current: SchemaVersion = .v4

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
