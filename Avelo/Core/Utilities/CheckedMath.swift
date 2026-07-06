import Foundation

public enum CheckedMath {
    public static func add(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw AppError.businessRule("Arithmetic overflow while \(context).")
        }
        return result.partialValue
    }

    public static func subtract(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard !result.overflow else {
            throw AppError.businessRule("Arithmetic overflow while \(context).")
        }
        return result.partialValue
    }

    public static func multiply(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw AppError.businessRule("Arithmetic overflow while \(context).")
        }
        return result.partialValue
    }

    public static func abs(_ value: Int64, context: String) throws -> Int64 {
        guard value != Int64.min else {
            throw AppError.businessRule("Arithmetic overflow while \(context).")
        }
        return Swift.abs(value)
    }

    public static func sum<S: Sequence>(_ values: S, context: String) throws -> Int64 where S.Element == Int64 {
        var total: Int64 = 0
        for value in values {
            total = try add(total, value, context: context)
        }
        return total
    }
}
