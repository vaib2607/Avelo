import SwiftUI

public struct VouchersView: View {

    @EnvironmentObject private var env: AppEnvironment
    @State private var holder = VouchersViewModelHolder()
    @State private var showTypeFilter: Bool = false

    public init() {}

    public var body: some View {
        VouchersContent(holder: holder, showTypeFilter: $showTypeFilter)
            .navigationTitle("Vouchers")
            .toolbar { toolbar }
            .onAppear { setup() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("New Journal") { env.router.present(.newJournal) }
                Button("New Payment") { env.router.present(.newPayment) }
                Button("New Receipt") { env.router.present(.newReceipt) }
                Button("New Contra")  { env.router.present(.newContra) }
                Button("New Purchase"){ env.router.present(.newPurchase) }
                Button("New Sales")   { env.router.present(.newSales) }
                Button("New Credit Note") { env.router.present(.newCreditNote) }
                Button("New Debit Note")  { env.router.present(.newDebitNote) }
            } label: {
                Label("New", systemImage: "plus")
            }
        }
    }

    private func setup() {
        guard let ctx = env.companyContext else { return }
        if holder.vm == nil || holder.vm?.companyId != ctx.companyId {
            holder.vm = VouchersViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            holder.vm?.reload()
        }
    }
}

@MainActor
final class VouchersViewModelHolder: ObservableObject {
    @Published var vm: VouchersViewModel?
}

@MainActor
private struct VouchersContent: View {
    @ObservedObject var holder: VouchersViewModelHolder
    @Binding var showTypeFilter: Bool

    var body: some View {
        if let vm = holder.vm {
            VouchersBody(vm: vm, showTypeFilter: $showTypeFilter)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct VouchersBody: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var vm: VouchersViewModel
    @Binding var showTypeFilter: Bool

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            Table(vm.vouchers) {
                TableColumn("Date") { v in
                    Text(DateFormatters.userDate.string(from: v.date))
                }
                TableColumn("Number", value: \.number)
                TableColumn("Type", value: \.voucherTypeCode.rawValue)
                TableColumn("Party") { v in
                    if let pid = v.partyAccountId {
                        Text(vm.accountName(pid))
                    } else { Text("—").foregroundStyle(.secondary) }
                }
                TableColumn("Narration") { v in
                    Text(v.narration).lineLimit(1).truncationMode(.tail)
                }
                TableColumn("Amount (₹)") { v in
                    Text(Currency.formatPaise(v.totalPaise))
                        .monospacedDigit()
                }
                TableColumn("Status") { v in
                    if v.isReversal {
                        StatusBadge(kind: .warning, text: "Reversal")
                    } else {
                        StatusBadge(kind: .success, text: "Posted")
                    }
                }
                TableColumn("Actions") { v in
                    HStack {
                        Button("Edit") { env.router.present(.editVoucher(v.id)) }
                            .disabled(v.isReversal)
                        Button("Reverse") { env.router.present(.reverseVoucher(v.id)) }
                            .disabled(v.isReversal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SearchBar(text: $vm.query, placeholder: "Search by narration / number / party…")
                Button { showTypeFilter.toggle() } label: {
                    Label("Type", systemImage: "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showTypeFilter) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filter by voucher type")
                            .font(.headline)
                        ForEach(VoucherType.Code.allCases) { code in
                            Toggle(code.rawValue, isOn: Binding(
                                get: { vm.typeFilter.contains(code) },
                                set: { isOn in
                                    if isOn { vm.typeFilter.insert(code) } else { vm.typeFilter.remove(code) }
                                }
                            ))
                        }
                        Divider()
                        DatePicker("From", selection: Binding(
                            get: { vm.fromDate ?? Date.distantPast },
                            set: { vm.fromDate = $0 }
                        ), displayedComponents: .date)
                        DatePicker("To", selection: Binding(
                            get: { vm.toDate ?? Date.distantFuture },
                            set: { vm.toDate = $0 }
                        ), displayedComponents: .date)
                        Button("Clear dates") {
                            vm.fromDate = nil
                            vm.toDate = nil
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 260)
                }
                Button("Apply") { vm.reload() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }
}
