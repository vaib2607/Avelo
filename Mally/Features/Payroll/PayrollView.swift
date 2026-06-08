import SwiftUI

public struct PayrollView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: PayrollViewModel?
    @State private var postFor: PayrollEmployee.ID?

    public init() {}

    public var body: some View {
        PayrollContent(vm: vm, postFor: $postFor)
            .navigationTitle("Payroll")
            .toolbar {
                ToolbarItem {
                    Button { env.router.present(.newEmployee) } label: {
                        Label("New Employee", systemImage: "plus")
                    }
                }
            }
            .onAppear { setup() }
            .onChange(of: env.companyContext?.companyId) { _, _ in setup() }
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = PayrollViewModel(companyId: ctx.companyId, db: ctx.database, fyId: ctx.financialYear.id)
            model.reload()
            vm = model
        }
    }
}

private struct IdWrap: Identifiable { let id: PayrollEmployee.ID }

@MainActor
private struct PayrollContent: View {
    let vm: PayrollViewModel?
    @Binding var postFor: PayrollEmployee.ID?

    var body: some View {
        if let vm {
            PayrollBody(vm: vm, postFor: $postFor)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct PayrollBody: View {
    @Bindable var vm: PayrollViewModel
    @Binding var postFor: PayrollEmployee.ID?

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack {
                    SearchBar(text: $vm.query, placeholder: "Search employees…")
                }
                .padding(12)
                Divider()
                Table(vm.filtered) {
                    TableColumn("Code", value: \.employeeCode)
                    TableColumn("Name", value: \.name)
                    TableColumn("Designation") { e in
                        Text(e.designation ?? "—")
                    }
                    TableColumn("Basic (₹)") { e in
                        Text(Currency.formatPaise(e.basicPaise)).monospacedDigit()
                    }
                    TableColumn("HRA (₹)") { e in
                        Text(Currency.formatPaise(e.hraPaise)).monospacedDigit()
                    }
                    TableColumn("Other (₹)") { e in
                        Text(Currency.formatPaise(e.otherAllowancesPaise)).monospacedDigit()
                    }
                    TableColumn("Status") { e in
                        StatusBadge(kind: e.isActive ? .success : .neutral,
                                    text: e.isActive ? "Active" : "Inactive")
                    }
                    TableColumn("Actions") { e in
                        Button("Post salary…") { postFor = e.id }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Entries for month \(String(format: "%04d-%02d", vm.monthYear / 100, vm.monthYear % 100))")
                        .font(.headline)
                    Spacer()
                }
                .padding(12)
                Divider()
                Table(vm.entries) {
                    TableColumn("Employee code", value: \.employeeCode)
                    TableColumn("Name", value: \.employeeName)
                    TableColumn("Gross (₹)") { e in
                        Text(Currency.formatPaise(e.grossPaise)).monospacedDigit()
                    }
                    TableColumn("Deduction (₹)") { e in
                        Text(Currency.formatPaise(e.deductionsPaise)).monospacedDigit()
                    }
                    TableColumn("Net (₹)") { e in
                        Text(Currency.formatPaise(e.netPaise)).monospacedDigit()
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { postFor.map { IdWrap(id: $0) } },
            set: { postFor = $0?.id }
        )) { wrap in
            PostSalarySheet(employeeId: wrap.id)
        }
    }
}
