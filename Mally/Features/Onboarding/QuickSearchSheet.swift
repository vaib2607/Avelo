import SwiftUI

/// Quick search (Cmd+/). Finds accounts by
/// code or name; Up/Down to move, Return to open, Esc to dismiss.
public struct QuickSearchSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var items: [Hit] = []
    @State private var loadError: String?
    @FocusState private var fieldFocused: Bool

    public init() {}

    private enum Kind: String { case account = "Ledger" }

    private struct Hit: Identifiable {
        let id = UUID()
        let kind: Kind
        let code: String
        let title: String
        let run: (AppRouter) -> Void
    }

    private var filtered: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search accounts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(runSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(14)
            Divider()
            content
            moveKeys
        }
        .frame(width: 560, height: 420)
        .onAppear { fieldFocused = true; load() }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            Spacer(); Text(loadError).foregroundStyle(.red); Spacer()
        } else {
            let hits = filtered
            if hits.isEmpty {
                Spacer()
                Text(query.isEmpty ? "Start typing to search" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            row(hit, highlighted: index == selectedIndex)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { run(hit) }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { _, idx in
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ hit: Hit, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(hit.code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            Text(hit.title)
            Spacer()
            Text(hit.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(highlighted ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var moveKeys: some View {
        ZStack {
            Button("") { move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { move(1) }.keyboardShortcut(.downArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func runSelected() {
        let hits = filtered
        guard hits.indices.contains(selectedIndex) else { return }
        run(hits[selectedIndex])
    }

    private func run(_ hit: Hit) {
        hit.run(env.router)
        dismiss()
    }

    private func load() {
        guard let ctx = env.companyContext else { return }
        do {
            var out: [Hit] = []
            let accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            for a in accounts {
                out.append(Hit(kind: .account, code: a.code, title: a.name) { $0.openLedger(a.id) })
            }
            self.items = out
        } catch {
            self.loadError = AppError.wrap(error).localizedMessage
        }
    }
}
