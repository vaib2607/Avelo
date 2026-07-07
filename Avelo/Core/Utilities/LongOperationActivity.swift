import Foundation

public protocol LongOperationActivityControlling: Sendable {
    func perform<T>(reason: String, operation: () throws -> T) throws -> T
    func perform<T>(reason: String, operation: () async throws -> T) async throws -> T
}

public struct ProcessInfoLongOperationActivityController: LongOperationActivityControlling {
    public init() {}

    public func perform<T>(reason: String, operation: () throws -> T) throws -> T {
        let processInfo = ProcessInfo.processInfo
        let token = processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
        defer { processInfo.endActivity(token) }
        return try operation()
    }

    public func perform<T>(reason: String, operation: () async throws -> T) async throws -> T {
        let processInfo = ProcessInfo.processInfo
        let token = processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
        defer { processInfo.endActivity(token) }
        return try await operation()
    }
}
