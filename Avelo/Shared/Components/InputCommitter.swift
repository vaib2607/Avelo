import Foundation

/// Synchronously flushes editor-local buffers before validation or posting.
/// It is UI scratch state only; it never writes financial data directly.
@MainActor
public final class InputCommitter {
    private var commits: [AnyHashable: () -> Void] = [:]

    public init() {}

    public func register(id: AnyHashable, commit: @escaping () -> Void) {
        commits[id] = commit
    }

    public func unregister(id: AnyHashable) {
        commits.removeValue(forKey: id)
    }

    public func commitAll() {
        for commit in commits.values { commit() }
    }
}
