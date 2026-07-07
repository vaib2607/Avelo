import SwiftUI

@MainActor
extension ReportsBody {
    @ViewBuilder
    var receivablesSection: some View {
        outstandingList(title: "Receivables")
    }

    @ViewBuilder
    var payablesSection: some View {
        outstandingList(title: "Payables")
    }

    @ViewBuilder
    var outstandingSection: some View {
        outstandingList(title: "Outstanding")
    }

    @ViewBuilder
    func outstandingList(title: String) -> some View {
        if let o = vm.outstanding {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Table(o.rows) {
                    TableColumn("Account") { r in
                        Button(r.partyName.capitalized) { openLedger(r.accountId) }
                            .buttonStyle(.plain)
                    }
                    TableColumn("Reference") { r in
                        Text(r.referenceNumber)
                    }
                    TableColumn("Amount (₹)") { r in
                        Text(Currency.formatPaise(r.amountPaise)).monospacedDigit()
                    }
                }
                Text("Total: \(Currency.formatPaise(o.totalPaise))").monospacedDigit().bold()
            }
        } else {
            EmptyStateView(
                title: "No outstanding items",
                message: "Outstanding balances appear when receivables or payables have unpaid bill allocations.",
                systemImage: "clock.arrow.circlepath",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

}
