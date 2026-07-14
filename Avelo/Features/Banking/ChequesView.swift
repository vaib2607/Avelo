import SwiftUI

@MainActor
struct ChequesContent: View {
    let vm: ChequesViewModel?

    var body: some View {
        if let vm {
            ChequesBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct ChequesBody: View {
    @Bindable var vm: ChequesViewModel
    @State private var bounceTarget: AccountingWorkflowsRepository.ChequeRegisterRow?
    @State private var representTarget: AccountingWorkflowsRepository.ChequeRegisterRow?
    @State private var bounceReason: String = ""
    @State private var representDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Status", selection: $vm.statusFilter) {
                    Text("All statuses").tag(ChequeStatus?.none)
                    ForEach(ChequeStatus.allCases) { s in
                        Text(s.rawValue.capitalized).tag(Optional(s))
                    }
                }
                .frame(width: 200)
                .onChange(of: vm.statusFilter) { _, _ in vm.reload() }
                Spacer()
            }
            .padding(12)
            Divider()
            if vm.rows.isEmpty {
                EmptyStateView(
                    title: "No cheques",
                    message: "Cheques recorded on Payment/Receipt vouchers appear here for bounce and re-presentation tracking.",
                    systemImage: "banknote",
                    actionTitle: "Refresh",
                    action: { vm.reload() }
                )
            } else {
                Table(vm.rows) {
                    TableColumn("Cheque #", value: \.cheque.chequeNumber)
                    TableColumn("Voucher", value: \.voucherNumber)
                    TableColumn("Party", value: \.partyName)
                    TableColumn("Amount (₹)") { row in
                        Text(Currency.formatPaise(row.amountPaise)).monospacedDigit()
                    }
                    TableColumn("Due date") { row in
                        Text(row.cheque.dueDate.map { DateFormatters.userDate.string(from: $0) } ?? "—")
                    }
                    TableColumn("Status") { row in
                        StatusBadge(kind: statusStyle(row.cheque.status), text: row.cheque.status.rawValue.capitalized)
                    }
                    TableColumn("Actions") { row in
                        HStack {
                            Button("Bounce…") { bounceTarget = row; bounceReason = "" }
                                .disabled(row.cheque.status != .issued && row.cheque.status != .deposited)
                            Button("Re-present…") { representTarget = row; representDate = Date() }
                                .disabled(row.cheque.status != .bounced)
                        }
                    }
                }
            }
        }
        .onAppear { vm.reload() }
        .sheet(item: $bounceTarget) { row in
            bounceSheet(row)
        }
        .sheet(item: $representTarget) { row in
            representSheet(row)
        }
    }

    private func bounceSheet(_ row: AccountingWorkflowsRepository.ChequeRegisterRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bounce cheque \(row.cheque.chequeNumber)").font(.title3.bold())
            Text("Posts a linked reversal voucher and marks the cheque bounced.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Reason *", text: $bounceReason)
            HStack {
                Spacer()
                Button("Cancel") { bounceTarget = nil }.keyboardShortcut(.cancelAction)
                Button("Bounce") {
                    vm.bounce(voucherId: row.cheque.voucherId, reason: bounceReason)
                    bounceTarget = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(bounceReason.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func representSheet(_ row: AccountingWorkflowsRepository.ChequeRegisterRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Re-present cheque \(row.cheque.chequeNumber)").font(.title3.bold())
            Text("Posts a new voucher for the re-presented cheque, linked back to the bounced original.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Re-presentation date", selection: $representDate, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { representTarget = nil }.keyboardShortcut(.cancelAction)
                Button("Re-present") {
                    vm.represent(voucherId: row.cheque.voucherId, on: representDate)
                    representTarget = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func statusStyle(_ status: ChequeStatus) -> StatusBadgeStyle {
        switch status {
        case .issued, .deposited: return .neutral
        case .cleared: return .success
        case .bounced: return .error
        case .cancelled: return .inactive
        }
    }
}
