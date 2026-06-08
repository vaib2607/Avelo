import SwiftUI

/// Tally-style account selector: recently-used accounts float to the top,
/// with live type-ahead over code and name. Up/Down to move, Return to pick,
/// Esc to close. Public API is unchanged from the previous Picker-based view.
public struct AccountPicker: View {
    @Binding public var selection: Account.ID?
    public var accounts: [Account]
    public var placeholder: String = "Choose account…"
    public var filter: ((Account) -> Bool)? = nil
    public var isEditable: Bool = true

    @State private var isExpanded: Bool = false
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    public init(selection: Binding<Account.ID?>,
                accounts: [Account],
                placeholder: String = "Choose account…",
                filter: ((Account) -> Bool)? = nil,
                isEditable: Bool = true) {
        self._selection = selection
        self.accounts = accounts
        self.placeholder = placeholder
        self.filter = filter
        self.isEditable = isEditable
    }

    public var body: some View {
        Button {
            query = ""
            selectedIndex = 0
            isExpanded = true
        } label: {
            HStack {
                Text(selectedLabel)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(!isEditable || sortedAccounts.isEmpty)
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var selectedLabel: String {
        if let id = selection, let acc = accounts.first(where: { $0.id == id }) {
            return "\(acc.code)  —  \(acc.name)"
        }
        return placeholder
    }

    @ViewBuilder
    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type code or name…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(pickSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(10)
            Divider()
            let matches = filteredAccounts
            if matches.isEmpty {
                Text("No matching account").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, acc in
                            row(acc, highlighted: index == selectedIndex)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { pick(acc) }
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 240)
                    .onChange(of: selectedIndex) { _, idx in
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
            moveKeys
        }
        .frame(width: 360)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private func row(_ acc: Account, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(acc.code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .leading)
            Text(acc.name).lineLimit(1)
            Spacer()
            if acc.id == selection {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 3)
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
        let count = filteredAccounts.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func pickSelected() {
        let matches = filteredAccounts
        guard matches.indices.contains(selectedIndex) else { return }
        pick(matches[selectedIndex])
    }

    private func pick(_ acc: Account) {
        selection = acc.id
        isExpanded = false
    }

    /// All eligible accounts, recently-used first then by code.
    private var sortedAccounts: [Account] {
        let base = filter.map { f in accounts.filter(f) } ?? accounts
        return base.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?) where l != r:
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                if lhs.code == rhs.code { return lhs.name < rhs.name }
                return lhs.code < rhs.code
            }
        }
    }

    private var filteredAccounts: [Account] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sortedAccounts }
        return sortedAccounts.filter {
            $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }
}
