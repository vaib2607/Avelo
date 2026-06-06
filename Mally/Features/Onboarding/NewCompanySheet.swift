import SwiftUI

public struct NewCompanySheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = OnboardingViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    companySection
                    fySection
                    inventorySection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 540)
        .onChange(of: vm.companyName) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.pan) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.gstin) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.fyLabel) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.fyStart) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.fyEnd) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.booksBegin) { _, _ in vm.refreshValidity() }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Company").font(.title2.bold())
            Spacer()
            Button { router.presentedSheet = nil } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var companySection: some View {
        GroupBox("Company") {
            Form {
                TextField("Legal name *", text: $vm.companyName)
                TextField("PAN (optional)", text: $vm.pan)
                    .textCase(.uppercase)
                TextField("GSTIN (optional)", text: $vm.gstin)
                    .textCase(.uppercase)
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var fySection: some View {
        GroupBox("Financial Year") {
            Form {
                TextField("Label *", text: $vm.fyLabel)
                DatePicker("Start *", selection: $vm.fyStart, displayedComponents: .date)
                DatePicker("End *", selection: $vm.fyEnd, displayedComponents: .date)
                DatePicker("Books begin *", selection: $vm.booksBegin, displayedComponents: .date)
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        GroupBox("Inventory") {
            Form {
                Toggle("Enable inventory", isOn: $vm.enableInventory)
                if vm.enableInventory {
                    Picker("Link mode", selection: $vm.inventoryMode) {
                        Text("Manual").tag(InventoryLinkMode.manual)
                        Text("Auto-prompt").tag(InventoryLinkMode.autoPrompt)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Create") { create() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canCreate)
        }
        .padding(16)
    }

    private func create() {
        env.isBusy = true
        Task {
            defer { env.isBusy = false }
            do {
                _ = try await CompanyService.create(
                    companyInput: CompanyInputValidator.Input(name: vm.companyName, gstin: vm.gstin, pan: vm.pan),
                    fyInput: FinancialYearInputValidator.Input(
                        label: vm.fyLabel, startDate: vm.fyStart, endDate: vm.fyEnd, booksBeginDate: vm.booksBegin
                    ),
                    seedDefaults: true,
                    manager: env.manager
                )
                if vm.enableInventory {
                    if let id = try? env.registry.firstId(named: vm.companyName) {
                        let ctx = await env.manager.openHandle(id: id)
                        if let ctx = ctx {
                            let svc = CompanyService(db: ctx.db, companyId: id, manager: env.manager)
                            try svc.setInventoryMode(enabled: true, linkMode: vm.inventoryMode)
                        }
                    }
                }
                env.showSuccess("Company created.")
                router.presentedSheet = nil
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }
}
