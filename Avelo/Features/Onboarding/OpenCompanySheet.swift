import SwiftUI

public struct OpenCompanySheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var entries: [CompanyRegistryEntry] = []
    @State private var query: String = ""
    @State private var isOpening: Bool = false

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
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.headline)
                            Text(entry.id.uuidString).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") {
                            guard !isOpening && !env.isBusy else { return }
                            isOpening = true
                            Task {
                                defer { isOpening = false }
                                await env.openCompany(entry.id)
                                router.presentedSheet = nil
                            }
                        }
                        .disabled(isOpening || env.isBusy)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .task {
            do {
                entries = try env.registry.listAll()
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }

    private var filtered: [CompanyRegistryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
