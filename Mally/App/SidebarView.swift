import SwiftUI

public struct SidebarView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(WindowState.self) private var windowState

    public init() {}

    public var body: some View {
        @Bindable var router = router
        @Bindable var windowState = windowState

        List(selection: $router.selection) {
            Section("Workspace") {
                if let ctx = env.companyContext {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentCompanyName)
                            .font(.headline)
                        Text(ctx.financialYear.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Modules") {
                ForEach(SidebarDestination.v1VisibleCases) { dest in
                    NavigationLink(value: dest) {
                        Label(dest.title, systemImage: dest.systemImage)
                    }
                    .ifLet(dest.shortcut) { view, key in
                        view.contextMenu { shortcutHint(key) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mally")
        .toolbar {
            ToolbarItem {
                Button {
                    windowState.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                }
            }
        }
    }

    private var currentCompanyName: String {
        guard let ctx = env.companyContext else { return "" }
        return ctx.companyName
    }

    @ViewBuilder
    private func shortcutHint(_ key: Character) -> some View {
        Text("Shortcut: ⌘\(key)")
    }
}

extension View {
    @ViewBuilder
    func ifLet<V, T: View>(_ value: V?, transform: (Self, V) -> T) -> some View {
        if let v = value {
            transform(self, v)
        } else {
            self
        }
    }
}
