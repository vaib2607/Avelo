<<<<<<< HEAD
import AppKit
=======
>>>>>>> origin/main
import SwiftUI

public struct NewCompanySheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm = OnboardingViewModel()
<<<<<<< HEAD
    @State private var createdRecoveryKey: String?
    @State private var recoveryAcknowledged: Bool = false
=======
>>>>>>> origin/main

    public init() {}

    public var body: some View {
        @Bindable var vm = vm

        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    companySection
                    fySection
                    chartSection
                    inventorySection
<<<<<<< HEAD
                    recoverySection
=======
>>>>>>> origin/main
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 540)
        .onChange(of: vm.companyName) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.addressLine1) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.addressLine2) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.city) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.state) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.pincode) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.country) { _, _ in vm.refreshValidity() }
        .onChange(of: vm.baseCurrency) { _, _ in vm.refreshValidity() }
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
<<<<<<< HEAD
            .disabled(createdRecoveryKey != nil && !recoveryAcknowledged)
=======
>>>>>>> origin/main
        }
        .padding(16)
    }

    @ViewBuilder
    private var companySection: some View {
        card(title: "Company") {
            inputField("Legal name *", text: $vm.companyName)
            inputField("Address line 1", text: $vm.addressLine1)
            inputField("Address line 2", text: $vm.addressLine2)
            inputField("City", text: $vm.city)
            inputField("State", text: $vm.state)
            inputField("Pincode", text: $vm.pincode)
            inputField("Country", text: $vm.country)
            inputField("Base currency", text: $vm.baseCurrency)
            inputField("PAN (optional)", text: $vm.pan)
                .textCase(.uppercase)
            inputField("GSTIN (optional)", text: $vm.gstin)
                .textCase(.uppercase)
        }
    }

    @ViewBuilder
    private var fySection: some View {
        card(title: "Financial Year") {
            inputField("Label *", text: $vm.fyLabel)
            labeledRow("Start *") {
                DatePicker("", selection: $vm.fyStart, displayedComponents: .date)
                    .labelsHidden()
            }
            labeledRow("End *") {
                DatePicker("", selection: $vm.fyEnd, displayedComponents: .date)
                    .labelsHidden()
            }
            labeledRow("Books begin *") {
                DatePicker("", selection: $vm.booksBegin, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        card(title: "Chart of Accounts") {
            Picker("Default chart", selection: $vm.defaultChart) {
                Text("Default").tag("Default")
            }
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        card(title: "Inventory") {
            Toggle("Enable inventory", isOn: $vm.enableInventory)
            if vm.enableInventory {
<<<<<<< HEAD
                Text("Ledger vouchers do not change stock automatically. Use explicit item invoices or manual stock movements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let createdRecoveryKey {
            card(title: "Recovery Key") {
                Text("Save this key now. Avelo does not store a recovery copy, and encrypted backups need it on another Mac.")
                    .foregroundStyle(.secondary)
                Text(createdRecoveryKey)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("Copy Recovery Key") {
                    copyRecoveryKey(createdRecoveryKey)
                }
                Toggle("I've saved this recovery key", isOn: $recoveryAcknowledged)
=======
                Picker("Link mode", selection: $vm.inventoryMode) {
                    Text("Manual").tag(InventoryLinkMode.manual)
                    Text("Auto-prompt").tag(InventoryLinkMode.autoPrompt)
                }
>>>>>>> origin/main
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 140, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func inputField(_ title: String, text: Binding<String>) -> some View {
        labeledRow(title) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
<<<<<<< HEAD
            Button(createdRecoveryKey == nil ? "Cancel" : "Close") { router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
                .disabled(createdRecoveryKey != nil && !recoveryAcknowledged)
            Button("Create") { create() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canCreate || createdRecoveryKey != nil || env.isBusy)
=======
            Button("Cancel") { router.presentedSheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Create") { create() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canCreate)
>>>>>>> origin/main
        }
        .padding(16)
    }

    private func create() {
<<<<<<< HEAD
        guard !env.isBusy else { return }
=======
>>>>>>> origin/main
        env.isBusy = true
        Task {
            defer { env.isBusy = false }
            do {
                let company = try await CompanyService.create(
                    companyInput: CompanyInputValidator.Input(
                        name: vm.companyName,
                        addressLine1: vm.addressLine1,
                        addressLine2: vm.addressLine2,
                        city: vm.city,
                        state: vm.state,
                        pincode: vm.pincode,
                        country: vm.country,
                        baseCurrency: vm.baseCurrency,
                        gstin: vm.gstin,
                        pan: vm.pan
                    ),
                    fyInput: FinancialYearInputValidator.Input(
                        label: vm.fyLabel, startDate: vm.fyStart, endDate: vm.fyEnd, booksBeginDate: vm.booksBegin
                    ),
                    seedDefaults: true,
                    manager: env.manager
                )
                await env.openCompany(company.id)
                if vm.enableInventory {
                    if let ctx = env.companyContext {
                        let svc = CompanyService(db: ctx.database, companyId: ctx.companyId, manager: env.manager)
<<<<<<< HEAD
                        try svc.setInventoryMode(enabled: true, linkMode: .manual)
                    }
                }
                env.notifyDataChanged()
                createdRecoveryKey = try await env.manager.recoveryKey(for: company.id)
                env.showSuccess("Company created. Save the recovery key before closing.")
=======
                        try svc.setInventoryMode(enabled: true, linkMode: vm.inventoryMode)
                    }
                }
                env.notifyDataChanged()
                env.showSuccess("Company created.")
                router.presentedSheet = nil
>>>>>>> origin/main
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }
<<<<<<< HEAD

    private func copyRecoveryKey(_ recoveryKey: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(recoveryKey, forType: .string)
    }
=======
>>>>>>> origin/main
}
