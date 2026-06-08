import Foundation

public enum SchemaVersion: Int, CaseIterable, Sendable, Comparable {
    case v1 = 1

    public static let current: SchemaVersion = .v1

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
