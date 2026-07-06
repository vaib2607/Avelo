import SwiftUI

public struct SettingsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: SettingsViewModel?
    @State private var costCentres: [CostCentre] = []
    @State private var costCategories: [CostCategory] = []
    @State private var masterErrorMessage: String?

    public init() {}

    public var body: some View {
        Group {
            if let vm = vm { content(vm: vm) } else { ProgressView() }
        }
        .navigationTitle("Settings")
        .overlay(alignment: .top) {
            ModuleChrome(
                title: "Settings",
                subtitle: "Company setup, inventory toggles, FY control, backup, restore, and preferences in one place.",
                hints: [
                    .init(title: "Backup", key: "⇧⌘B"),
                    .init(title: "Restore", key: "⇧⌘R"),
                    .init(title: "New FY", key: "⌘N")
                ]
            )
        }
        .safeAreaInset(edge: .bottom) {
            ModuleFooterBar(items: [
                .init(title: "Next", detail: "Use company, FY, and feature rows to tune the active company."),
                .init(title: "Shortcut", detail: "⇧⌘B backs up; ⇧⌘R restores from a local file."),
                .init(title: "Workflow", detail: "Feature toggles affect downstream inventory and reporting screens.")
            ])
        }
        .alert("Feature unavailable", isPresented: Binding(
            get: { masterErrorMessage != nil },
            set: { if !$0 { masterErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { masterErrorMessage = nil }
        } message: {
            Text(masterErrorMessage ?? "This feature is unavailable.")
        }
        .toolbar {
            if let ctx = env.companyContext, let vm {
                ToolbarItem {
                    Picker("FY", selection: Binding(
                        get: { ctx.financialYear.id },
                        set: { env.switchFinancialYear($0) }
                    )) {
                        ForEach(vm.financialYears) { fy in
                            Text(fy.label).tag(fy.id)
                        }
                    }
                    .frame(width: 170)
                }
            }
        }
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
                    Button("Edit company info…") { env.router.present(.companyInfo) }
                    Button("Backup now…") { env.router.present(.backup) }
                    Button("Restore from backup…") { env.router.present(.restore) }
                }
            }
            Section("Cost Masters") {
                HStack {
                    Button("New Cost Centre") {
                        masterErrorMessage = "Cost centres are deferred outside the frozen schema."
                    }
                    Button("New Cost Category") {
                        masterErrorMessage = "Cost categories are deferred outside the frozen schema."
                    }
                    Spacer()
                }
                Text("Cost masters are currently unavailable in the frozen schema.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Table(costCentres) {
                    TableColumn("Code", value: \.code)
                    TableColumn("Name", value: \.name)
                    TableColumn("Status") { c in
                        StatusBadge(kind: c.isActive ? .success : .neutral, text: c.isActive ? "Active" : "Inactive")
                    }
                    TableColumn("Actions") { c in
                        HStack {
                            Button("Edit") {
                                masterErrorMessage = "Cost centres are deferred outside the frozen schema."
                            }
                            Button("Disable") { disableCostCentre(c.id) }
                                .disabled(!c.isActive)
                        }
                    }
                }
                Table(costCategories) {
                    TableColumn("Code", value: \.code)
                    TableColumn("Name", value: \.name)
                    TableColumn("Status") { c in
                        StatusBadge(kind: c.isActive ? .success : .neutral, text: c.isActive ? "Active" : "Inactive")
                    }
                    TableColumn("Actions") { c in
                        HStack {
                            Button("Edit") {
                                masterErrorMessage = "Cost categories are deferred outside the frozen schema."
                            }
                            Button("Disable") { disableCostCategory(c.id) }
                                .disabled(!c.isActive)
                        }
                    }
                }
            }
            Section("Company Features") {
                Toggle("Enable inventory", isOn: Binding(
                    get: { vm.company?.isInventoryEnabled ?? false },
                    set: { vm.setInventoryEnabled($0) }
                ))
                Picker("Inventory link mode", selection: Binding(
                    get: { vm.company?.inventoryLinkMode ?? .manual },
                    set: { vm.setInventoryLinkMode($0) }
                )) {
                    ForEach(InventoryLinkMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!(vm.company?.isInventoryEnabled ?? false))
                HStack {
                    Button("Inventory Settings…") { env.router.present(.manageInventory) }
                    Button("Payroll Settings…") { env.router.present(.managePayroll) }
                    Spacer()
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
                    Button("About Avelo…") { env.router.present(.about) }
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
        reloadMasters()
    }

    private func reloadMasters() {
        guard let ctx = env.companyContext else { return }
        do {
            let svc = MasterDataService(db: ctx.database, companyId: ctx.companyId)
            costCentres = try svc.listCostCentres()
            costCategories = try svc.listCostCategories()
        } catch let appError as AppError {
            switch appError {
            case .featureUnavailable:
                costCentres = []
                costCategories = []
            default:
                env.showError(appError)
            }
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func disableCostCentre(_ id: CostCentre.ID) {
        guard let ctx = env.companyContext else { return }
        do {
            try MasterDataService(db: ctx.database, companyId: ctx.companyId).disableCostCentre(id)
            reloadMasters()
            env.notifyDataChanged()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }

    private func disableCostCategory(_ id: CostCategory.ID) {
        guard let ctx = env.companyContext else { return }
        do {
            try MasterDataService(db: ctx.database, companyId: ctx.companyId).disableCostCategory(id)
            reloadMasters()
            env.notifyDataChanged()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
