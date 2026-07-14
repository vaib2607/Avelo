import SwiftUI

private struct OrderIdWrap: Identifiable { let id: InventoryOrder.ID }

@MainActor
struct OrdersContent: View {
    let vm: InventoryOrdersViewModel?

    var body: some View {
        if let vm {
            OrdersBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct OrdersBody: View {
    @Bindable var vm: InventoryOrdersViewModel
    @State private var newOrderType: InventoryOrderType?
    @State private var detailOrderId: InventoryOrder.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Type", selection: $vm.typeFilter) {
                    Text("All types").tag(InventoryOrderType?.none)
                    Text("Purchase").tag(Optional(InventoryOrderType.purchaseOrder))
                    Text("Sales").tag(Optional(InventoryOrderType.salesOrder))
                }
                .frame(width: 180)
                .onChange(of: vm.typeFilter) { _, _ in vm.reload() }
                Picker("Status", selection: $vm.statusFilter) {
                    Text("All statuses").tag(InventoryOrderStatus?.none)
                    ForEach(InventoryOrderStatus.allCases) { s in
                        Text(s.rawValue.capitalized).tag(Optional(s))
                    }
                }
                .frame(width: 180)
                .onChange(of: vm.statusFilter) { _, _ in vm.reload() }
                Spacer()
                Button("New Purchase Order") { newOrderType = .purchaseOrder }
                Button("New Sales Order") { newOrderType = .salesOrder }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            if vm.orders.isEmpty {
                EmptyStateView(
                    title: "No orders",
                    message: "Create a purchase or sales order to track pending fulfilment.",
                    systemImage: "shippingbox",
                    actionTitle: "New Sales Order",
                    action: { newOrderType = .salesOrder }
                )
            } else {
                Table(vm.orders) {
                    TableColumn("Number") { o in
                        Button(o.number) { detailOrderId = o.id }.buttonStyle(.plain)
                    }
                    TableColumn("Type") { o in
                        Text(o.orderType == .salesOrder ? "Sales" : "Purchase")
                    }
                    TableColumn("Order date") { o in
                        Text(DateFormatters.userDate.string(from: o.orderDate))
                    }
                    TableColumn("Expected") { o in
                        Text(o.expectedDate.map { DateFormatters.userDate.string(from: $0) } ?? "—")
                    }
                    TableColumn("Status") { o in
                        StatusBadge(kind: statusStyle(o.status), text: o.status.rawValue.capitalized)
                    }
                    TableColumn("Actions") { o in
                        HStack {
                            Button("Details…") { detailOrderId = o.id }
                            Button("Close") { vm.closeOrder(o.id) }
                                .disabled(o.status != .open)
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { newOrderType.map { OrderTypeWrap(type: $0) } },
            set: { newOrderType = $0?.type }
        )) { wrap in
            NewOrderSheet(orderType: wrap.type) { vm.reload() }
        }
        .sheet(item: Binding(
            get: { detailOrderId.map { OrderIdWrap(id: $0) } },
            set: { detailOrderId = $0?.id }
        )) { wrap in
            OrderDetailSheet(orderId: wrap.id) { vm.reload() }
        }
    }

    private func statusStyle(_ status: InventoryOrderStatus) -> StatusBadgeStyle {
        switch status {
        case .open: return .neutral
        case .closed: return .success
        case .cancelled: return .error
        }
    }
}

private struct OrderTypeWrap: Identifiable {
    let type: InventoryOrderType
    var id: String { type.rawValue }
}
