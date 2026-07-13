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
                        ("Cmd+2", "Open Vouchers"),
                        ("Cmd+3", "Open Accounts"),
                        ("Cmd+4", "Open Reports"),
                        ("Cmd+5", "Open Inventory"),
                        ("Cmd+6", "Open GST"),
                        ("Cmd+7", "Open Payroll"),
                        ("Cmd+8", "Open Banking"),
                        ("Cmd+9", "Open Audit log"),
                        ("Cmd+0", "Open Settings"),
                    ])

                    section("Vouchers (function keys)", rows: [
                        ("F4", "New Contra voucher"),
                        ("F5", "New Payment voucher"),
                        ("F6", "New Receipt voucher"),
                        ("F7", "New Journal voucher"),
                        ("Cmd+K → Memo", "Journal-style memo entry"),
                        ("F8", "New Sales voucher"),
                        ("F9", "New Purchase voucher"),
                        ("⌃F8", "New Credit Note"),
                        ("⌃F9", "New Debit Note"),
                    ])

                    section("Reports (Cmd+Opt)", rows: [
                        ("Cmd+Opt+1", "Trial Balance"),
                        ("Cmd+Opt+2", "Profit & Loss"),
                        ("Cmd+Opt+3", "Balance Sheet"),
                        ("Cmd+Opt+4", "GST Summary"),
                        ("Cmd+Opt+5", "Day Book"),
                        ("Cmd+Opt+6", "Ledger"),
                        ("Cmd+Opt+7", "Cash Book"),
                        ("Cmd+Opt+8", "Bank Book"),
                        ("Cmd+Opt+9", "Receivables"),
                        ("Cmd+Opt+0", "Payables"),
                        ("Cmd+Opt+Shift+1", "Cash Flow"),
                        ("Cmd+Opt+Shift+2", "Stock Ageing"),
                    ])

                    section("Other", rows: [
                        ("Cmd+K", "Open command palette"),
                        ("Cmd+/", "Quick search"),
                        ("Cmd+,", "Show this shortcut help"),
                        ("Company menu", "Open company info, backup, restore, and company-level actions"),
                        ("Cmd+Shift+N", "New company"),
                        ("Cmd+Shift+B", "Backup current company"),
                        ("Cmd+Shift+R", "Restore backup"),
                        ("Company → Inventory Settings", "Open inventory configuration"),
                        ("Company → Payroll Settings", "Open payroll configuration"),
                        ("Company → Lock FY", "Lock the active financial year"),
                        ("Company → Close FY", "Close the active financial year"),
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
