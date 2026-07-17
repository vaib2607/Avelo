import SwiftUI

/// Tally-style account selector: recently-used accounts float to the top,
/// with live type-ahead over code and name. Up/Down to move, Return to pick,
/// Esc to close. Public API is unchanged from the previous Picker-based view.
public struct AccountPicker: View {
    @Binding public var selection: Account.ID?
    public var accounts: [Account]
    public var placeholder: String = "Choose account…"
    public var filter: ((Account) -> Bool)? = nil
<<<<<<< HEAD
    public var eligibility: ((Account) -> AccountEligibility)? = nil
    public var isEditable: Bool = true
    public var onCreate: (() -> Void)? = nil
    /// Fired after a selection is committed (Return or click), once the
    /// popover has closed — lets the host move focus to the next field in a
    /// Tally-style Enter cascade without this component knowing about it.
    public var onCommitSelection: (() -> Void)? = nil
    /// Two-way link to a host-owned focus flag (e.g. a `@FocusState` enum
    /// case wrapped in a computed `Binding`). When the host sets this true,
    /// the picker focuses and opens itself — used to auto-advance into the
    /// next ledger field in a Tally-style Enter cascade.
    public var isFocusedExternally: Binding<Bool>? = nil
=======
    public var isEditable: Bool = true
>>>>>>> origin/main

    @State private var isExpanded: Bool = false
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
<<<<<<< HEAD
    @FocusState private var pickerButtonFocused: Bool
    @FocusState private var searchFieldFocused: Bool
=======
    @FocusState private var fieldFocused: Bool
>>>>>>> origin/main

    public init(selection: Binding<Account.ID?>,
                accounts: [Account],
                placeholder: String = "Choose account…",
                filter: ((Account) -> Bool)? = nil,
<<<<<<< HEAD
                eligibility: ((Account) -> AccountEligibility)? = nil,
                isEditable: Bool = true,
                onCreate: (() -> Void)? = nil,
                onCommitSelection: (() -> Void)? = nil,
                isFocusedExternally: Binding<Bool>? = nil) {
=======
                isEditable: Bool = true) {
>>>>>>> origin/main
        self._selection = selection
        self.accounts = accounts
        self.placeholder = placeholder
        self.filter = filter
<<<<<<< HEAD
        self.eligibility = eligibility
        self.isEditable = isEditable
        self.onCreate = onCreate
        self.onCommitSelection = onCommitSelection
        self.isFocusedExternally = isFocusedExternally
=======
        self.isEditable = isEditable
>>>>>>> origin/main
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
<<<<<<< HEAD
                if selectedEligibility?.isEligible == false {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(selectedEligibility?.rejectionReason ?? "This account is no longer eligible.")
                }
=======
>>>>>>> origin/main
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
<<<<<<< HEAD
        .focusable()
        .focused($pickerButtonFocused)
        .onChange(of: pickerButtonFocused) { _, focused in
            isFocusedExternally?.wrappedValue = focused
        }
        .onChange(of: isFocusedExternally?.wrappedValue) { _, external in
            guard external == true else { return }
            query = ""
            selectedIndex = 0
            pickerButtonFocused = true
            isExpanded = true
        }
        .onKeyPress("c", phases: .down, action: handleCreateAccountShortcut)
        // Keep the picker reachable when it can create an account. This
        // matters most for filtered fields (for example cash/bank): an empty
        // eligible list must not also hide the Alt+C escape hatch.
        .disabled(!isEditable || (sortedAccounts.isEmpty && onCreate == nil))
=======
        .disabled(!isEditable || sortedAccounts.isEmpty)
>>>>>>> origin/main
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

<<<<<<< HEAD
    private var selectedEligibility: AccountEligibility? {
        guard let id = selection,
              let account = accounts.first(where: { $0.id == id }) else { return nil }
        return eligibility?(account)
    }

=======
>>>>>>> origin/main
    @ViewBuilder
    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type code or name…", text: $query)
                    .textFieldStyle(.plain)
<<<<<<< HEAD
                    .focused($searchFieldFocused)
                    .onKeyPress("c", phases: .down, action: handleCreateAccountShortcut)
=======
                    .focused($fieldFocused)
>>>>>>> origin/main
                    .onSubmit(pickSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(10)
            Divider()
            let matches = filteredAccounts
            if matches.isEmpty {
<<<<<<< HEAD
                VStack(spacing: 10) {
                    Text("No matching account").foregroundStyle(.secondary)
                    if onCreate != nil {
                        Button("Create account…", action: requestAccountCreation)
                    }
                }
                .padding(16)
=======
                Text("No matching account").foregroundStyle(.secondary).padding(16)
>>>>>>> origin/main
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
<<<<<<< HEAD
            if onCreate != nil {
                Divider()
                Button(action: requestAccountCreation) {
                    Label("Create account…", systemImage: "plus")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            moveKeys
        }
        .frame(width: 360)
        .onAppear { searchFieldFocused = true }
=======
            moveKeys
        }
        .frame(width: 360)
        .onAppear { fieldFocused = true }
>>>>>>> origin/main
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
<<<<<<< HEAD
        closePopover()
        onCommitSelection?()
    }

    private func handleCreateAccountShortcut(_ keyPress: KeyPress) -> KeyPress.Result {
        guard onCreate != nil,
              keyPress.modifiers.contains(.option),
              pickerButtonFocused || searchFieldFocused else {
            return .ignored
        }
        requestAccountCreation()
        return .handled
    }

    private func requestAccountCreation() {
        guard let onCreate else { return }
        closePopover()
        onCreate()
    }

    private func closePopover() {
        isExpanded = false
        pickerButtonFocused = false
        searchFieldFocused = false
=======
        isExpanded = false
>>>>>>> origin/main
    }

    /// All eligible accounts, recently-used first then by code.
    private var sortedAccounts: [Account] {
<<<<<<< HEAD
        let filteredByLegacyClosure = filter.map { f in accounts.filter(f) } ?? accounts
        let base = eligibility.map { evaluate in
            filteredByLegacyClosure.filter { evaluate($0).isEligible }
        } ?? filteredByLegacyClosure
        return base.sorted { lhs, rhs in
            let lhsRank = eligibility?(lhs).ranking ?? 0
            let rhsRank = eligibility?(rhs).ranking ?? 0
            if lhsRank != rhsRank { return lhsRank > rhsRank }
=======
        let base = filter.map { f in accounts.filter(f) } ?? accounts
        return base.sorted { lhs, rhs in
>>>>>>> origin/main
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
<<<<<<< HEAD
        }.sorted { lhs, rhs in
            let lhsCodeExact = lhs.code.lowercased() == q
            let rhsCodeExact = rhs.code.lowercased() == q
            if lhsCodeExact != rhsCodeExact { return lhsCodeExact }
            let lhsNameExact = lhs.name.lowercased() == q
            let rhsNameExact = rhs.name.lowercased() == q
            if lhsNameExact != rhsNameExact { return lhsNameExact }
            let lhsRank = eligibility?(lhs).ranking ?? 0
            let rhsRank = eligibility?(rhs).ranking ?? 0
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                if lhs.code == rhs.code { return lhs.name < rhs.name }
                return lhs.code < rhs.code
            }
=======
>>>>>>> origin/main
        }
    }
}
