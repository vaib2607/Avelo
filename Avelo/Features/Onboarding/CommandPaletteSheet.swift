import SwiftUI

/// Spotlight-style command palette (Cmd+K). Lists navigation destinations,
/// voucher-entry actions, and creation shortcuts; filters as you type;
/// Up/Down to move, Return to run, Esc to dismiss.
public struct CommandPaletteSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    public init() {}

    private struct Command: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbol: String
        let run: (AppRouter) -> Void
    }

    private var allCommands: [Command] {
        var out: [Command] = []
        func nav(_ title: String, _ symbol: String, _ dest: SidebarDestination) {
            out.append(Command(title: title, subtitle: "Go", symbol: symbol) { $0.go(dest) })
        }
        nav("Dashboard", "square.grid.2x2", .dashboard)
        nav("Accounts", "book", .accounts)
        nav("Vouchers", "doc.text", .vouchers)
        nav("Reports", "chart.bar", .reports)
        nav("Inventory", "shippingbox", .inventory)
        nav("GST", "doc.text.magnifyingglass", .gst)
        nav("Payroll", "person.3", .payroll)
        nav("Banking", "building.columns", .banking)
        nav("Audit", "lock.shield", .audit)
        nav("Settings", "gearshape", .settings)
        out.append(Command(title: "Company Info", subtitle: "Edit local company profile", symbol: "building.2") { $0.present(.companyInfo) })

        func voucher(_ title: String, _ key: String, _ sheet: RouterSheet) {
            out.append(Command(title: "New \(title)", subtitle: "Voucher · \(key)", symbol: "plus.rectangle") { $0.present(sheet) })
        }
        voucher("Contra", "F4", .newContra)
        voucher("Payment", "F5", .newPayment)
        voucher("Receipt", "F6", .newReceipt)
        voucher("Journal", "F7", .newJournal)
        out.append(Command(title: "Memo", subtitle: "Journal-style note", symbol: "note.text") { $0.present(.newJournal) })
        voucher("Sales", "F8", .newSales)
        voucher("Purchase", "F9", .newPurchase)
        voucher("Credit Note", "F10", .newCreditNote)
        voucher("Debit Note", "F11", .newDebitNote)

        out.append(Command(title: "New Account", subtitle: "Create", symbol: "plus.circle") { $0.present(.newAccount) })
        out.append(Command(title: "Backup Company", subtitle: "Action", symbol: "externaldrive") { $0.present(.backup) })
        out.append(Command(title: "Financial Year Settings", subtitle: "Open Settings", symbol: "calendar") { $0.go(.settings) })
        out.append(Command(title: "Inventory Settings", subtitle: "Open Settings", symbol: "shippingbox") { $0.go(.settings) })
        out.append(Command(title: "Payroll Settings", subtitle: "Open Settings", symbol: "person.3") { $0.go(.settings) })
        out.append(Command(title: "Cash Book", subtitle: "Report", symbol: "book.closed") { $0.openReport(.cashBook) })
        out.append(Command(title: "Bank Book", subtitle: "Report", symbol: "building.columns") { $0.openReport(.bankBook) })
        out.append(Command(title: "Receivables", subtitle: "Report", symbol: "tray.full") { $0.openReport(.receivables) })
        out.append(Command(title: "Payables", subtitle: "Report", symbol: "tray.and.arrow.down") { $0.openReport(.payables) })
        out.append(Command(title: "Outstanding", subtitle: "Report", symbol: "clock.arrow.circlepath") { $0.openReport(.outstanding) })
        out.append(Command(title: "Stock Summary", subtitle: "Report", symbol: "shippingbox") { $0.openReport(.stockValuation) })
        out.append(Command(title: "Stock Movement", subtitle: "Report", symbol: "arrow.left.arrow.right") { $0.openReport(.stockMovement) })
        out.append(Command(title: "Stock Register", subtitle: "Report", symbol: "list.bullet.rectangle") { $0.openReport(.stockRegister) })
        out.append(Command(title: "GST Filing Views", subtitle: "Report", symbol: "doc.text.magnifyingglass") { $0.openReport(.gstFiling) })
        return out
    }

    private var filtered: [Command] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allCommands }
        return allCommands.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(runSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(14)
            Divider()
            resultsList
            moveKeys
        }
        .frame(width: 560, height: 420)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var resultsList: some View {
        let items = filtered
        if items.isEmpty {
            Spacer()
            Text("No matching commands").foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, cmd in
                        row(cmd, highlighted: index == selectedIndex)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(cmd) }
                    }
                }
                .listStyle(.plain)
                .onChange(of: selectedIndex) { _, idx in
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ cmd: Command, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.symbol).frame(width: 22).foregroundStyle(.secondary)
            Text(cmd.title)
            Spacer()
            Text(cmd.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(highlighted ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    /// Hidden buttons give us Up/Down arrow handling without a focus fight.
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
        let items = filtered
        guard items.indices.contains(selectedIndex) else { return }
        run(items[selectedIndex])
    }

    private func run(_ cmd: Command) {
        cmd.run(env.router)
        dismiss()
    }
}
