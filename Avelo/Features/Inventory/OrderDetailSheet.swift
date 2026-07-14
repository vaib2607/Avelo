import SwiftUI

public struct OrderDetailSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let orderId: InventoryOrder.ID
    let onChanged: () -> Void

    @State private var order: InventoryOrder?
    @State private var lines: [InventoryOrderLine] = []
    @State private var items: [InventoryItem.ID: InventoryItem] = [:]
    @State private var party: Account?
    @State private var fulfillmentInput: [InventoryOrderLine.ID: String] = [:]
    @State private var showCancelConfirm = false

    public init(orderId: InventoryOrder.ID, onChanged: @escaping () -> Void) {
        self.orderId = orderId
        self.onChanged = onChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(order?.number ?? "Order").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            if let order {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection(order)
                        linesSection(order)
                    }
                    .padding(16)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel Order") { showCancelConfirm = true }
                        .disabled(order.status != .open)
                    Button("Close Order") { closeOrder() }
                        .buttonStyle(.borderedProminent)
                        .disabled(order.status != .open)
                }
                .padding(16)
                .confirmationDialog("Cancel this order?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                    Button("Cancel Order", role: .destructive) { cancelOrder() }
                    Button("Keep Order", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
            } else {
                ProgressView().padding(40)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { load() }
    }

    private func summarySection(_ order: InventoryOrder) -> some View {
        GroupBox("Order") {
            VStack(alignment: .leading, spacing: 8) {
                row("Type", order.orderType == .salesOrder ? "Sales Order" : "Purchase Order")
                row("Party", party?.name ?? "—")
                row("Order date", DateFormatters.userDate.string(from: order.orderDate))
                row("Expected date", order.expectedDate.map { DateFormatters.userDate.string(from: $0) } ?? "—")
                HStack(alignment: .top) {
                    Text("Status").foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                    StatusBadge(kind: statusKind(order.status), text: order.status.rawValue.capitalized)
                }
            }
            .padding(8)
        }
    }

    private func linesSection(_ order: InventoryOrder) -> some View {
        GroupBox("Lines") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Ordered").frame(width: 80, alignment: .trailing)
                    Text("Fulfilled").frame(width: 90, alignment: .trailing)
                    Text("Rate (₹)").frame(width: 100, alignment: .trailing)
                    Text("").frame(width: 140)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(lines) { line in
                    lineRow(line, editable: order.status == .open)
                }
            }
            .padding(8)
        }
    }

    private func lineRow(_ line: InventoryOrderLine, editable: Bool) -> some View {
        HStack {
            Text(items[line.itemId].map { "\($0.code) — \($0.name)" } ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(line.quantity)").frame(width: 80, alignment: .trailing).monospacedDigit()
            Text("\(line.fulfilledQuantity)").frame(width: 90, alignment: .trailing).monospacedDigit()
            Text(Currency.formatPaise(line.unitRatePaise)).frame(width: 100, alignment: .trailing).monospacedDigit()
            if editable {
                HStack {
                    TextField("Qty", text: Binding(
                        get: { fulfillmentInput[line.id] ?? String(line.fulfilledQuantity) },
                        set: { fulfillmentInput[line.id] = $0 }
                    ))
                    .frame(width: 70)
                    Button("Update") { recordFulfillment(line) }
                }
                .frame(width: 140)
            } else {
                Text("").frame(width: 140)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusKind(_ status: InventoryOrderStatus) -> StatusBadgeStyle {
        switch status {
        case .open: return .neutral
        case .closed: return .success
        case .cancelled: return .error
        }
    }

    private func load() {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = InventoryOrderService(db: ctx.database, companyId: ctx.companyId)
            guard let loaded = try svc.orders().first(where: { $0.id == orderId }) else {
                throw AppError.notFound("Order")
            }
            order = loaded
            lines = try svc.linesForOrder(orderId)
            let inventoryRepo = InventoryRepository(db: ctx.database)
            items = Dictionary(uniqueKeysWithValues: lines.compactMap { line in
                (try? inventoryRepo.findItemById(line.itemId)).flatMap { $0 }.map { (line.itemId, $0) }
            })
            party = try AccountRepository(db: ctx.database).findById(loaded.partyAccountId)
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func recordFulfillment(_ line: InventoryOrderLine) {
        guard let ctx = env.companyContext,
              let text = fulfillmentInput[line.id],
              let quantity = Int64(text.trimmingCharacters(in: .whitespaces)) else { return }
        do {
            try InventoryOrderService(db: ctx.database, companyId: ctx.companyId).recordFulfillment(orderLineId: line.id, fulfilledQuantity: quantity)
            load()
            onChanged()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func closeOrder() {
        guard let ctx = env.companyContext else { return }
        do {
            try InventoryOrderService(db: ctx.database, companyId: ctx.companyId).closeOrder(orderId)
            load()
            onChanged()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func cancelOrder() {
        guard let ctx = env.companyContext else { return }
        do {
            try InventoryOrderService(db: ctx.database, companyId: ctx.companyId).cancelOrder(orderId)
            load()
            onChanged()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
