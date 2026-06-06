import SwiftUI

public struct OpenCompanySheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var entries: [CompanyRegistryEntry] = []
    @State private var query: String = ""

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
                            Task {
                                await env.openCompany(entry.id)
                                router.presentedSheet = nil
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .task {
            entries = (try? env.registry.listAll()) ?? []
        }
    }

    private var filtered: [CompanyRegistryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
