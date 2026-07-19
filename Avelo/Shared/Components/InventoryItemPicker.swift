import SwiftUI

/// Feature-neutral inventory selection control. Selection is committed only
/// through `onCommitSelection`; voucher sheets use that boundary for their
/// Enter cascade instead of observing raw row mutations themselves.
public struct InventoryItemPicker: View {
    @Binding private var selection: InventoryItem.ID?
    private let items: [InventoryItem]
    private let placeholder: String
    private let onCommitSelection: (() -> Void)?
    private let isFocusedExternally: Binding<Bool>?
    @State private var isExpanded = false
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var pickerButtonFocused: Bool
    @FocusState private var searchFieldFocused: Bool

    public init(selection: Binding<InventoryItem.ID?>,
                items: [InventoryItem],
                placeholder: String = "Choose item…",
                onCommitSelection: (() -> Void)? = nil,
                isFocusedExternally: Binding<Bool>? = nil) {
        _selection = selection
        self.items = items
        self.placeholder = placeholder
        self.onCommitSelection = onCommitSelection
        self.isFocusedExternally = isFocusedExternally
    }

    public var body: some View {
        Button {
            query = ""
            selectedIndex = 0
            isExpanded = true
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .lineLimit(1)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable()
        .focused($pickerButtonFocused)
        .onChange(of: pickerButtonFocused) { _, focused in
            isFocusedExternally?.wrappedValue = focused
        }
        .onChange(of: isFocusedExternally?.wrappedValue) { _, focused in
            guard focused == true else { return }
            query = ""
            selectedIndex = 0
            pickerButtonFocused = true
            isExpanded = true
        }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) { popoverContent }
        .accessibilityLabel(placeholder)
    }

    private var selectedLabel: String {
        guard let selection, let item = items.first(where: { $0.id == selection }) else { return placeholder }
        return "\(item.code) — \(item.name)"
    }

    private var filteredItems: [InventoryItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return items }
        return items.filter {
            $0.code.localizedCaseInsensitiveContains(normalized)
                || $0.name.localizedCaseInsensitiveContains(normalized)
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type item code or name…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .onSubmit(commitSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(10)
            Divider()
            if filteredItems.isEmpty {
                Text("No matching item")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Text(item.code).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            Text(item.name).lineLimit(1)
                            Spacer()
                            if item.id == selection { Image(systemName: "checkmark").font(.caption) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { commit(item) }
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .listStyle(.plain)
                .frame(height: 240)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
            }
        }
        .frame(width: 360)
        .onAppear { searchFieldFocused = true }
    }

    private func commitSelected() {
        let matches = filteredItems
        guard matches.indices.contains(selectedIndex) else { return }
        commit(matches[selectedIndex])
    }

    private func move(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func commit(_ item: InventoryItem) {
        selection = item.id
        isExpanded = false
        pickerButtonFocused = false
        searchFieldFocused = false
        onCommitSelection?()
    }
}
