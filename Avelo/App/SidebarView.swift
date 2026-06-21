import SwiftUI

public struct SidebarView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        @Bindable var router = router

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
            Section("Active Module") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gateway > \(router.selection.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(router.selection.title)
                        .font(.headline)
                    Text(moduleHint(for: router.selection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Modules") {
                ForEach(SidebarDestination.visibleCases) { dest in
                    NavigationLink(value: dest) {
                        HStack {
                            Label(dest.title, systemImage: dest.systemImage)
                            Spacer()
                            if let key = dest.shortcut {
                                Text("⌘\(key)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .ifLet(dest.shortcut) { view, key in
                        view.contextMenu { shortcutHint(key) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Avelo")
    }

    private var currentCompanyName: String {
        guard let ctx = env.companyContext else { return "" }
        return ctx.companyName
    }

    private func moduleHint(for destination: SidebarDestination) -> String {
        switch destination {
        case .dashboard: return "Overview and quick entry"
        case .vouchers: return "Post and reverse transactions"
        case .accounts: return "Groups and ledgers"
        case .reports: return "Statements and drill-down"
        case .inventory: return "Stock masters and movement"
        case .gst: return "GST summary and filing prep"
        case .payroll: return "Employees and salary posting"
        case .banking: return "Statement import and reconciliation"
        case .audit: return "Change history"
        case .settings: return "Company and FY controls"
        }
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
