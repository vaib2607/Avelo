import SwiftUI

@MainActor
extension ReportsBody {
    @ViewBuilder
    var dayBookSection: some View {
        let rows = vm.dayBook
        if rows.isEmpty {
            EmptyStateView(
                title: "No day book entries",
                message: "No vouchers were posted in the selected date range.",
                systemImage: "calendar.badge.clock",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            Table(rows) {
                TableColumn("Date") { r in
                    Text(DateFormatters.userDate.string(from: r.date))
                }
                TableColumn("Voucher") { r in
                    Button(r.voucherNumber) { openVoucher(r.id) }
                        .buttonStyle(.plain)
                }
                TableColumn("Type") { r in
                    Text(r.voucherTypeCode.rawValue)
                }
                TableColumn("Particulars") { r in
                    Text(r.narration)
                }
                TableColumn("Amount (₹)") { r in
                    Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                }
                // AVL-P1-037 (Day Book browse/drill/correct): Edit and
                // Reverse reachable directly from the row, matching
                // VouchersView's action set, instead of forcing a detour
                // through the Vouchers list to correct an entry found here.
                // Both dismiss back to this same Day Book — env.dataRevision
                // triggers ReportsView's existing reload-on-change, and
                // Table's row identity (Voucher.ID) keeps scroll position
                // stable across that reload.
                TableColumn("Actions") { r in
                    HStack {
                        Button("Edit") { openVoucher(r.id) }
                        Button("Reverse") { env.router.present(.reverseVoucher(r.id)) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var ledgerSection: some View {
        if let l = vm.ledger {
            VStack(alignment: .leading, spacing: 8) {
                        Text(l.accountName.capitalized).font(.headline)
                Table(l.entries) {
                    TableColumn("Date") { e in
                        Text(DateFormatters.userDate.string(from: e.date))
                    }
                    TableColumn("Voucher") { e in
                        Button(e.voucherNumber) { openVoucher(e.voucherId) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Particulars", value: \.narration)
                    TableColumn("Debit (₹)") { e in
                        Text(Currency.formatPaise(e.debitPaise)).monospacedDigit()
                    }
                    TableColumn("Credit (₹)") { e in
                        Text(Currency.formatPaise(e.creditPaise)).monospacedDigit()
                    }
                    TableColumn("Balance (₹)") { e in
                        Text(Currency.formatPaise(e.balancePaise)).monospacedDigit()
                    }
                }
                Text("Opening: \(Currency.formatPaise(l.openingBalancePaise))")
                    .monospacedDigit()
                Text("Closing: \(Currency.formatPaise(l.closingBalancePaise))")
                    .monospacedDigit()
                    .bold()
            }
        } else {
            EmptyStateView(
                title: "No ledger selected",
                message: "Choose an account to view its ledger entries for the selected period.",
                systemImage: "book.closed",
            )
        }
    }

}
