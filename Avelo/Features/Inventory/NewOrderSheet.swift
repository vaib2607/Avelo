import SwiftUI

public struct NewOrderSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let orderType: InventoryOrderType
    let onSaved: () -> Void

    @State private var accounts: [Account] = []
    @State private var company: Company?
    @State private var groups: [AccountGroup] = []
    @State private var eligibilityPolicy = AccountEligibilityPolicy()
    @State private var items: [InventoryItem] = []
    @State private var partyAccountId: Account.ID?
    @State private var number: String = ""
    @State private var orderDate: Date = Date()
    @State private var expectedDate: Date?
    @State private var hasExpectedDate: Bool = false
    @State private var lines: [OrderLineRow] = [OrderLineRow()]

    public init(orderType: InventoryOrderType, onSaved: @escaping () -> Void) {
        self.orderType = orderType
        self.onSaved = onSaved
    }

    struct OrderLineRow: Identifiable {
        let id = UUID()
        var itemId: InventoryItem.ID?
        var quantity: String = ""
        var rate: String = "0.00"
    }

    private var title: String { orderType == .salesOrder ? "New Sales Order" : "New Purchase Order" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Order number *", text: $number)
                AccountPicker(
                    selection: $partyAccountId,
                    accounts: accounts,
                    placeholder: "Party *",
                    eligibility: partyEligibility
                )
                DatePicker("Order date", selection: $orderDate, displayedComponents: .date)
                Toggle("Expected date", isOn: $hasExpectedDate)
                if hasExpectedDate {
                    DatePicker("Expected date", selection: Binding(
                        get: { expectedDate ?? Date() },
                        set: { expectedDate = $0 }
                    ), displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            GroupBox("Lines") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Qty").frame(width: 90, alignment: .leading)
                        Text("Rate (₹)").frame(width: 120, alignment: .leading)
                        Text("").frame(width: 32)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach($lines) { line in
                        lineRow(line: line)
                    }
                    Button { lines.append(OrderLineRow()) } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .padding(.horizontal, 16)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { load() }
    }

    private func lineRow(line: Binding<OrderLineRow>) -> some View {
        HStack {
            Picker("", selection: line.itemId) {
                Text("Choose item…").tag(InventoryItem.ID?.none)
                ForEach(items) { item in
                    Text("\(item.code) — \(item.name)").tag(Optional(item.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: line.quantity)
                .frame(width: 90)
            MoneyTextField(label: "", text: line.rate, onCommit: {})
                .frame(width: 120)
            Button { lines.removeAll { $0.id == line.wrappedValue.id } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(lines.count <= 1)
            .frame(width: 32)
        }
    }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
            && partyAccountId != nil
            && lines.contains { $0.itemId != nil && (Int64($0.quantity.trimmingCharacters(in: .whitespaces)) ?? 0) > 0 }
    }

    private func load() {
        guard let ctx = env.companyContext else { return }
        do {
            accounts = try AccountService(db: ctx.database, companyId: ctx.companyId).listActiveAccounts()
            company = try CompanyRepository(db: ctx.database).findById(ctx.companyId)
            groups = try AccountGroupRepository(db: ctx.database).listForCompany(ctx.companyId)
            eligibilityPolicy = try AccountEligibilityPolicy.loading(db: ctx.database, companyId: ctx.companyId)
            items = try InventoryRepository(db: ctx.database).listItems(
                filter: .init(companyId: ctx.companyId, includeArchived: false, limit: 2000, offset: 0)
            )
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func save() {
        guard let ctx = env.companyContext, let partyAccountId else { return }
        do {
            let draftLines: [InventoryOrderService.DraftLine] = lines.compactMap { row in
                guard let itemId = row.itemId, let qty = Int64(row.quantity.trimmingCharacters(in: .whitespaces)), qty > 0 else { return nil }
                let ratePaise = Currency.parseRupeeInput(row.rate) ?? 0
                return .init(itemId: itemId, quantity: qty, unitRatePaise: ratePaise)
            }
            _ = try InventoryOrderService(db: ctx.database, companyId: ctx.companyId).createOrder(
                type: orderType,
                number: number,
                partyAccountId: partyAccountId,
                orderDate: orderDate,
                expectedDate: hasExpectedDate ? expectedDate : nil,
                lines: draftLines
            )
            env.showSuccess("Order created.")
            onSaved()
            dismiss()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func partyEligibility(_ account: Account) -> AccountEligibility {
        guard let company else {
            return AccountEligibility(isEligible: false, rejectionReason: "Company context is unavailable.")
        }
        return eligibilityPolicy.evaluate(
            account: account,
            for: .orderParty(orderType),
            company: company,
            groups: groups
        )
    }
}
