import SwiftUI

@MainActor
extension ReportsBody {
    @ViewBuilder
    var stockMovementSection: some View {
        if vm.stockMovements.isEmpty {
            EmptyStateView(
                title: "No stock movements",
                message: "There were no stock movements posted in the selected period.",
                systemImage: "arrow.left.arrow.right",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Movement").font(.headline)
                Table(vm.stockMovements) {
                    TableColumn("Date") { row in
                        Text(DateFormatters.userDate.string(from: row.date))
                    }
                    TableColumn("Item") { row in
                        Text(row.itemId.uuidString.prefix(8).description)
                    }
                    TableColumn("Type", value: \.movementType.rawValue)
                    TableColumn("Qty") { row in
                        Text(String(format: "%.3f", row.quantity))
                    }
                    TableColumn("Voucher") { row in
                        if let voucherId = row.voucherId {
                            Button(row.referenceVoucherNumber ?? "Open") { openVoucher(voucherId) }
                                .buttonStyle(.plain)
                        } else {
                            Text(row.referenceVoucherNumber ?? "—")
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder
    var stockRegisterSection: some View {
        if vm.stockRegisterRows.isEmpty {
            EmptyStateView(
                title: "No stock register rows",
                message: "The selected period has no item-level stock activity to list in the register.",
                systemImage: "list.bullet.rectangle",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Register").font(.headline)
                Table(vm.stockRegisterRows) {
                    TableColumn("Item") { row in
                        Text(row.itemName)
                    }
                    TableColumn("Date") { row in
                        Text(DateFormatters.userDate.string(from: row.movement.date))
                    }
                    TableColumn("Type", value: \.movement.movementType.rawValue)
                    TableColumn("Qty") { row in
                        Text(String(format: "%.3f", row.movement.quantity))
                    }
                    TableColumn("Voucher") { row in
                        if let voucherId = row.movement.voucherId {
                            Button(row.movement.referenceVoucherNumber ?? "Open") { openVoucher(voucherId) }
                                .buttonStyle(.plain)
                        } else {
                            Text(row.movement.referenceVoucherNumber ?? "—")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var stockSummarySection: some View {
        if let s = vm.stockValuation {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Summary").font(.headline)
                Table(s.rows) {
                    TableColumn("Item", value: \.itemName)
                    TableColumn("Code", value: \.itemCode)
                    TableColumn("Quantity") { r in
                        Text(String(format: "%.3f", r.quantity))
                    }
                    TableColumn("Rate (₹)") { r in
                        Text(Currency.formatPaise(r.ratePaise)).monospacedDigit()
                    }
                    TableColumn("Value (₹)") { r in
                        Text(Currency.formatPaise(r.valuePaise)).monospacedDigit()
                    }
                }
                Text("Total: \(Currency.formatPaise(s.totalPaise))").monospacedDigit().bold()
            }
        } else {
            EmptyStateView(
                title: "No stock summary",
                message: "Select a different date range or stock movement mode to see stock valuation rows.",
                systemImage: "shippingbox",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    @ViewBuilder
    var stockAgeingSection: some View {
        if let s = vm.stockAgeing {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock Ageing").font(.headline)
                Table(s.rows) {
                    TableColumn("Item", value: \.itemName)
                    TableColumn("On hand") { row in
                        Text("\(row.onHandQty) \(row.unit)")
                    }
                    TableColumn("0-30") { row in Text("\(row.age0to30Qty)") }
                    TableColumn("31-60") { row in Text("\(row.age31to60Qty)") }
                    TableColumn("61-90") { row in Text("\(row.age61to90Qty)") }
                    TableColumn("90+") { row in Text("\(row.age90PlusQty)") }
                    TableColumn("Value (₹)") { row in
                        Text(Currency.formatPaise(row.onHandValuePaise)).monospacedDigit()
                    }
                }
            }
        } else {
            EmptyStateView(
                title: "No stock ageing",
                message: "Stock ageing is empty when inventory is disabled or no stock is on hand.",
                systemImage: "calendar.badge.clock",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }
}
