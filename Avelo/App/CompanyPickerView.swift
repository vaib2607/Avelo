import SwiftUI

public struct CompanyPickerView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router

    @State private var entries: [CompanyRegistryEntry] = []
    @State private var isLoading: Bool = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 480)
        .task(id: env.dataRevision) { await reload() }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Avelo")
                    .font(.largeTitle.bold())
                Text("Offline accounting for small businesses.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    router.present(.newCompany)
                } label: {
                    Label("New Company", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .controlSize(.large)

                Button {
                    router.present(.restore)
                } label: {
                    Label("Restore Backup", systemImage: "tray.and.arrow.down")
                }
                .controlSize(.large)

                Button {
                    Task {
                        do {
                            let entry = try await DemoCompanySeeder.ensureDemoCompany(manager: env.manager)
                            await env.openCompany(entry.id)
                        } catch {
                            env.showError(AppError.wrap(error))
                        }
                    }
                } label: {
                    Label("Demo Company", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            EmptyStateView(
                title: "No companies yet",
                message: "Create a new company to get started. Everything stays on this Mac.",
                systemImage: "building.2",
                actionTitle: "New Company"
            ) {
                router.present(.newCompany)
            }
        } else {
            List {
                ForEach(entries) { entry in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.headline)
                            Text("ID: \(entry.id.uuidString.prefix(8))…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") {
                            Task { await env.openCompany(entry.id) }
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
    }

    private func reload() async {
        defer { isLoading = false }
        do {
            entries = try env.registry.listAll()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
