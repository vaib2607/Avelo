import SwiftUI

public struct OpenCompanySheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var entries: [CompanyRegistryEntry] = []
    @State private var query: String = ""
    @State private var rowActions = OpenCompanyRowActionState()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open Company").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            SearchBar(text: $query, placeholder: "Search companies…")
                .padding(12)
            List {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.name).font(.headline)
                                Text(entry.id.uuidString).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                guard rowActions.beginOpen(entry.id, appIsBusy: env.isBusy) else { return }
                                Task {
                                    defer { rowActions.finish() }
                                    await env.openCompany(entry.id)
                                    router.presentedSheet = nil
                                }
                            } label: {
                                Label("Open", systemImage: "arrow.right.circle")
                            }
                            .disabled(!rowActions.canStart(entry.id, appIsBusy: env.isBusy))

                            Button(role: .destructive) {
                                rowActions.requestDelete(entry.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(!rowActions.canStart(entry.id, appIsBusy: env.isBusy))
                        }

                        if rowActions.pendingDeleteCompanyId == entry.id {
                            ConfirmationDialog(
                                title: "Delete company?",
                                message: "This removes \(entry.name)'s local company database, sidecar files, registry entry, and stored encryption key.",
                                confirmTitle: "Delete",
                                isDestructive: true,
                                onConfirm: {
                                    guard rowActions.beginDelete(entry.id, appIsBusy: env.isBusy) else { return }
                                    Task {
                                        defer { rowActions.finish() }
                                        await env.deleteCompany(entry.id)
                                        await reloadCompanies()
                                    }
                                },
                                onCancel: { rowActions.cancelDelete() }
                            )
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await reloadCompanies() }
    }

    private var filtered: [CompanyRegistryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @MainActor
    private func reloadCompanies() async {
        do {
            entries = try env.registry.listAll()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}

public struct OpenCompanyRowActionState: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case opening(Company.ID)
        case deleting(Company.ID)
    }

    public private(set) var activeAction: Action?
    public private(set) var pendingDeleteCompanyId: Company.ID?

    public init() {}

    public func canStart(_ id: Company.ID, appIsBusy: Bool) -> Bool {
        guard !appIsBusy else { return false }
        return activeAction == nil
    }

    @discardableResult
    public mutating func beginOpen(_ id: Company.ID, appIsBusy: Bool) -> Bool {
        guard canStart(id, appIsBusy: appIsBusy) else { return false }
        pendingDeleteCompanyId = nil
        activeAction = .opening(id)
        return true
    }

    public mutating func requestDelete(_ id: Company.ID) {
        guard activeAction == nil else { return }
        pendingDeleteCompanyId = id
    }

    public mutating func cancelDelete() {
        pendingDeleteCompanyId = nil
    }

    @discardableResult
    public mutating func beginDelete(_ id: Company.ID, appIsBusy: Bool) -> Bool {
        guard pendingDeleteCompanyId == id, canStart(id, appIsBusy: appIsBusy) else { return false }
        pendingDeleteCompanyId = nil
        activeAction = .deleting(id)
        return true
    }

    public mutating func finish() {
        activeAction = nil
    }
}
