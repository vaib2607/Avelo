import SwiftUI

public struct ModuleFooterBar: View {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let title: String
        public let detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var body: some View {
        if !items.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.bold())
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.id != items.last?.id {
                        Divider().frame(height: 24)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
