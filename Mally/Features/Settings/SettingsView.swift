import SwiftUI

public struct SettingsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: SettingsViewModel?

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm { content(vm: vm) } else { ProgressView() }
        }
        .navigationTitle("Settings")
        .task(id: reloadKey) { setup() }
    }

    private var reloadKey: String {
        let company = env.companyContext?.companyId.uuidString ?? "none"
        return "\(company)-\(env.dataRevision)"
    }

    @ViewBuilder
    private func content(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm

        Form {
            Section("Company") {
                if let ctx = env.companyContext {
                    LabeledContent("Company ID", value: ctx.companyId.uuidString)
                    LabeledContent("Current FY", value: ctx.financialYear.label)
                    Button("Backup now…") { env.router.present(.backup) }
                    Button("Restore from backup…") { env.router.present(.restore) }
                }
            }
            Section("Financial years") {
                Table(vm.financialYears) {
                    TableColumn("Label", value: \.label)
                    TableColumn("Start") { fy in
                        Text(DateFormatters.userDate.string(from: fy.startDate))
                    }
                    TableColumn("End") { fy in
                        Text(DateFormatters.userDate.string(from: fy.endDate))
                    }
                    TableColumn("Status") { fy in
                        if fy.isClosed {
                            StatusBadge(kind: .neutral, text: "Closed")
                        } else if fy.isLocked {
                            StatusBadge(kind: .warning, text: "Locked")
                        } else {
                            StatusBadge(kind: .success, text: "Open")
                        }
                    }
                    TableColumn("Actions") { fy in
                        HStack {
                            if fy.isLocked {
                                Button("Unlock") { vm.unlock(fy.id) }
                            } else {
                                Button("Lock") { vm.lock(fy.id) }
                            }
                            Button("Close") { vm.close(fy.id) }
                                .disabled(fy.isClosed)
                        }
                    }
                }
                Button("New financial year…") { env.router.present(.newFinancialYear) }
            }
            Section("Preferences") {
                Button("Open preferences…") { env.router.present(.preferences) }
            }
            Section("About") {
                Button("About Mally…") { env.router.present(.about) }
            }
        }
        .formStyle(.grouped)
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = SettingsViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
    }
}
