import Foundation

public enum ValidationResult: Sendable, Equatable {
    case valid
    case invalid([ValidationError])

    public var errors: [ValidationError] {
        if case .invalid(let e) = self { return e }
        return []
    }

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public func merging(_ other: ValidationResult) -> ValidationResult {
        switch (self, other) {
        case (.valid, .valid):
            return .valid
        case (.valid, .invalid(let e)):
            return .invalid(e)
        case (.invalid(let e), .valid):
            return .invalid(e)
        case (.invalid(let a), .invalid(let b)):
            return .invalid(a + b)
        }
    }
}
