import SwiftUI

public struct PaginationState: Sendable, Equatable {
    public var limit: Int
    public var offset: Int
    public var totalCount: Int

    public init(limit: Int = 200, offset: Int = 0, totalCount: Int = 0) {
        self.limit = max(1, limit)
        self.offset = max(0, offset)
        self.totalCount = max(0, totalCount)
    }

    public var pageIndex: Int { offset / limit }
    public var pageCount: Int { max(1, Int(ceil(Double(totalCount) / Double(limit)))) }
    public var canGoPrevious: Bool { offset > 0 }
    public var canGoNext: Bool { offset + limit < totalCount }
    public var firstVisibleRecord: Int { totalCount == 0 ? 0 : offset + 1 }
    public var lastVisibleRecord: Int { min(offset + limit, totalCount) }

    public mutating func reset() {
        offset = 0
    }

    public mutating func goPrevious() {
        offset = max(0, offset - limit)
    }

    public mutating func goNext() {
        guard canGoNext else { return }
        offset += limit
    }
}

public struct PaginationControls: View {
    public let state: PaginationState
    public let isLoading: Bool
    public let previous: () -> Void
    public let next: () -> Void

    public init(state: PaginationState,
                isLoading: Bool,
                previous: @escaping () -> Void,
                next: @escaping () -> Void) {
        self.state = state
        self.isLoading = isLoading
        self.previous = previous
        self.next = next
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: previous) {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!state.canGoPrevious || isLoading)
            Button(action: next) {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!state.canGoNext || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var summary: String {
        guard state.totalCount > 0 else { return "0 records" }
        return "\(state.firstVisibleRecord)-\(state.lastVisibleRecord) of \(state.totalCount)"
    }
}
