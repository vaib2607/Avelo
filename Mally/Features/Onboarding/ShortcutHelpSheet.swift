import SwiftUI

public struct ShortcutHelpSheet: View {

    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Navigation", rows: [
                        ("Esc", "Back / cancel current action"),
                        ("Return / Enter", "Drill down (open selected item)"),
                        ("R", "Reload current view"),
                        ("Cmd+1", "Open Dashboard"),
                        ("Cmd+2", "Open Accounts"),
                        ("Cmd+3", "Open Vouchers"),
                        ("Cmd+4", "Open Reports"),
                        ("Cmd+5", "Open Inventory"),
                        ("Cmd+6", "Open Payroll"),
                        ("Cmd+7", "Open Banking"),
                        ("Cmd+8", "Open Audit log"),
                        ("Cmd+9", "Open Settings"),
                    ])

                    section("Vouchers (function keys)", rows: [
                        ("F4", "New Contra voucher"),
                        ("F5", "New Payment voucher"),
                        ("F6", "New Receipt voucher"),
                        ("F7", "New Journal voucher"),
                        ("F8", "New Sales voucher"),
                        ("F9", "New Purchase voucher"),
                        ("F10", "New Credit Note"),
                        ("F11", "New Debit Note"),
                    ])

                    section("Other", rows: [
                        ("Cmd+K", "Open command palette"),
                        ("Cmd+/", "Quick search"),
                        ("Cmd+,", "Show this shortcut help"),
                        ("Cmd+Shift+N", "New company"),
                        ("Cmd+Shift+B", "Backup current company"),
                    ])
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    @ViewBuilder
    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 140, alignment: .leading)
                        Text(row.1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
