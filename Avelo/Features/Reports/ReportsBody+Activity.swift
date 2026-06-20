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
