import Foundation

public enum SchemaVersion: Int, CaseIterable, Sendable, Comparable {
    case v1 = 1
    case v2 = 2
    case v3 = 3
    case v4 = 4
    case v5 = 5
    case v6 = 6
    case v7 = 7
    case v8 = 8
    case v9 = 9
    case v10 = 10
    case v11 = 11
    case v12 = 12

    public static let current: SchemaVersion = .v12

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
