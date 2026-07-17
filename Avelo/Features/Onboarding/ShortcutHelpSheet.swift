import SwiftUI

public struct ShortcutHelpSheet: View {

    @Environment(AppEnvironment.self) private var env
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
                    section("Navigation", rows: navigationRows)

                    section("Vouchers (function keys)", rows: voucherRows)

                    section("Reports (Cmd+Opt)", rows: reportRows)

                    section("Other", rows: otherRows)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    private var inventoryEnabled: Bool { env.companyContext?.isInventoryEnabled ?? false }

    private var navigationRows: [(String, String)] {
        var rows = [
            ("Esc", "Back / cancel current action"),
            ("Return / Enter", "Drill down (open selected item)"),
            ("R", "Reload current view"),
            ("Cmd+1", "Open Dashboard"),
            ("Cmd+2", "Open Vouchers"),
            ("Cmd+3", "Open Accounts"),
            ("Cmd+4", "Open Reports")
        ]
        if inventoryEnabled { rows.append(("Cmd+5", "Open Inventory")) }
        rows += [
            ("Cmd+6", "Open GST"),
            ("Cmd+7", "Open Payroll"),
            ("Cmd+8", "Open Banking"),
            ("Cmd+9", "Open Audit log"),
            ("Cmd+0", "Open Settings")
        ]
        return rows
    }

    /// Sourced from `AppActionRegistry` so this list can't drift from the
    /// Voucher menu/toolbar/palette. "Memo" has no registry entry (it's
    /// `.newJournal` under another name), so it stays hand-written.
    private var voucherRows: [(String, String)] {
        var rows: [(String, String)] = []
        for type: VoucherType.Code in [.contra, .payment, .receipt, .journal] {
            if let action = AppActionRegistry.action(for: .voucherCreate(type)), let key = action.shortcutLabel {
                rows.append((key, "\(action.title) voucher"))
            }
        }
        rows.append(("Cmd+K → Memo", "Journal-style memo entry"))
        for type: VoucherType.Code in [.sales, .purchase] {
            if let action = AppActionRegistry.action(for: .voucherCreate(type)), let key = action.shortcutLabel {
                rows.append((key, "\(action.title) voucher"))
            }
        }
        for type: VoucherType.Code in [.creditNote, .debitNote] {
            if let action = AppActionRegistry.action(for: .voucherCreate(type)), let key = action.shortcutLabel {
                rows.append((key, action.title))
            }
        }
        return rows
    }

    private var reportRows: [(String, String)] {
        var rows = [
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
            ("Cmd+Opt+Shift+1", "Cash Flow")
        ]
        if inventoryEnabled { rows.append(("Cmd+Opt+Shift+2", "Stock Ageing")) }
        return rows
    }

    private var otherRows: [(String, String)] {
        var rows = [
            ("Cmd+K", "Open command palette"),
            ("Cmd+/", "Quick search"),
            ("Cmd+,", "Show this shortcut help"),
            ("Company menu", "Open company info, backup, restore, and company-level actions"),
            ("Cmd+Shift+N", "New company"),
            ("Cmd+Shift+B", "Backup current company"),
            ("Cmd+Shift+R", "Restore backup")
        ]
        if inventoryEnabled { rows.append(("Company → Inventory Settings", "Open inventory configuration")) }
        rows += [
            ("Company → Payroll Settings", "Open payroll configuration"),
            ("Company → Lock FY", "Lock the active financial year"),
            ("Company → Close FY", "Close the active financial year")
        ]
        return rows
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
