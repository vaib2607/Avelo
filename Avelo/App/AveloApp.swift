import SwiftUI
import AppKit

struct AveloApp: App {

    @State private var environment: AppEnvironment?
    @State private var keyboardBridge: KeyboardBridge?
    private let selfTestRequested: Bool

    init() {
        let requested = SelfTestHarness.isRequested
        self.selfTestRequested = requested
        _environment = State(initialValue: requested ? nil : AppEnvironment())
        _keyboardBridge = State(initialValue: requested ? nil : KeyboardBridge())
    }

    var body: some Scene {
        WindowGroup {
            if selfTestRequested {
                Color.clear
                    .frame(width: 1, height: 1)
                    .task {
                        await SelfTestHarness.runAndExit()
                    }
            } else if let environment, let keyboardBridge {
                RootView()
                    .environment(environment)
                    .environment(environment.router)
                    .environment(keyboardBridge)
                    .frame(minWidth: 1080, minHeight: 720)
                    .onAppear {
                        environment.keyboard.onCommand = { [weak keyboardBridge] cmd in
                            keyboardBridge?.dispatch(cmd)
                        }
                        KeyboardMonitor.shared.onSuppressedKey = { [weak keyboardBridge] in
                            keyboardBridge?.flashSuppressed()
                        }
                        KeyboardMonitor.shared.install(router: environment.keyboard)
                    }
                    .onDisappear {
                        KeyboardMonitor.shared.uninstall()
                    }
            }
        }
        .windowStyle(.titleBar)
        .commands {
            if !selfTestRequested, let environment {
                CommandMenu("Company") {
                    Button("New Company…") {
                        NotificationCenter.default.post(name: .aveloRequestNewCompany, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Button("Company Info…") {
                        environment.router.present(.companyInfo)
                    }

                    Button("Open Company…") {
                        NotificationCenter.default.post(name: .aveloRequestOpenCompany, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                    Button("Backup…") {
                        NotificationCenter.default.post(name: .aveloRequestBackup, object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                    Button("Restore Backup…") {
                        NotificationCenter.default.post(name: .aveloRequestRestore, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    Button("Lock Financial Year…") {
                        NotificationCenter.default.post(name: .aveloRequestLockFy, object: nil)
                    }

                    Button("Close Financial Year…") {
                        NotificationCenter.default.post(name: .aveloRequestCloseFy, object: nil)
                    }

                    Button("Preferences…") {
                        NotificationCenter.default.post(name: .aveloRequestPreferences, object: nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)

                    Divider()

                    Button("Close Company") {
                        NotificationCenter.default.post(name: .aveloRequestCloseCompany, object: nil)
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(environment.companyContext == nil)
                }
                SidebarCommands()
                ToolbarCommands()
                CommandGroup(after: .pasteboard) {
                    Button("Open Company…") {
                        NotificationCenter.default.post(name: .aveloRequestOpenCompany, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
                // Canonical module shortcut scheme lives in `SidebarDestination.shortcut`.
                // Keep this menu, `KeyboardMonitor`, and the sidebar labels in sync.
                CommandMenu("Go") {
                    Button("Dashboard") { environment.router.go(.dashboard) }
                        .keyboardShortcut("1", modifiers: .command)
                    actionButton(.vouchersDisplay, environment: environment)
                    actionButton(.accountsDisplay, environment: environment)
                    Button("Reports")   { environment.router.go(.reports) }
                        .keyboardShortcut("4", modifiers: .command)
                    if environment.companyContext?.isInventoryEnabled == true {
                        Button("Inventory") { environment.router.go(.inventory) }
                            .keyboardShortcut("5", modifiers: .command)
                    }
                    Button("GST")       { environment.router.go(.gst) }
                        .keyboardShortcut("6", modifiers: .command)
                    Button("Payroll")   { environment.router.go(.payroll) }
                        .keyboardShortcut("7", modifiers: .command)
                    Button("Banking")   { environment.router.go(.banking) }
                        .keyboardShortcut("8", modifiers: .command)
                    Button("Audit")     { environment.router.go(.audit) }
                        .keyboardShortcut("9", modifiers: .command)
                    Button("Settings")  { environment.router.go(.settings) }
                        .keyboardShortcut("0", modifiers: .command)
                }
                CommandMenu("Masters") {
                    actionButton(.accountCreate, environment: environment)
                    Button("New Group…") { environment.router.present(.newGroup) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    if environment.companyContext?.isInventoryEnabled == true {
                        Button("New Item…") { environment.router.present(.newItem) }
                            .keyboardShortcut("i", modifiers: [.command, .shift])
                    }
                    Button("New Employee…") { environment.router.present(.newEmployee) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("New Financial Year…") { environment.router.present(.newFinancialYear) }
                        .keyboardShortcut("y", modifiers: [.command, .shift])
                    Divider()
                    Button("New Cost Centre…") { environment.router.present(.newCostCentre) }
                    Button("New Cost Category…") { environment.router.present(.newCostCategory) }
                }
                CommandMenu("Voucher") {
                    voucherActionButton(.contra, environment: environment)
                    voucherActionButton(.payment, environment: environment)
                    voucherActionButton(.receipt, environment: environment)
                    voucherActionButton(.journal, environment: environment)
                    Button("Memo")            { environment.router.present(.newJournal) }
                    voucherActionButton(.sales, environment: environment)
                    voucherActionButton(.purchase, environment: environment)
                    voucherActionButton(.creditNote, environment: environment)
                    voucherActionButton(.debitNote, environment: environment)
                }
                CommandMenu("Reports") {
                    actionButton(.trialBalanceDisplay, environment: environment)
                    Button("Profit & Loss") { environment.router.openReport(.profitLoss) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("Balance Sheet") { environment.router.openReport(.balanceSheet) }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                    Button("GST Summary") { environment.router.openReport(.gstSummary) }
                        .keyboardShortcut("4", modifiers: [.command, .option])
                    actionButton(.dayBookDisplay, environment: environment)
                    Button("Ledger") { environment.router.openReport(.ledger) }
                        .keyboardShortcut("6", modifiers: [.command, .option])
                    Button("Cash Book") { environment.router.openReport(.cashBook) }
                        .keyboardShortcut("7", modifiers: [.command, .option])
                    Button("Bank Book") { environment.router.openReport(.bankBook) }
                        .keyboardShortcut("8", modifiers: [.command, .option])
                    Button("Receivables") { environment.router.openReport(.receivables) }
                        .keyboardShortcut("9", modifiers: [.command, .option])
                    Button("Payables") { environment.router.openReport(.payables) }
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    Button("Outstanding") { environment.router.openReport(.outstanding) }
                    if environment.companyContext?.isInventoryEnabled == true {
                        Button("Stock Summary") { environment.router.openReport(.stockValuation) }
                        Button("Stock Movement") { environment.router.openReport(.stockMovement) }
                        Button("Stock Register") { environment.router.openReport(.stockRegister) }
                    }
                    Button("GST Filing Views") { environment.router.openReport(.gstFiling) }
                    Button("Cash Flow") { environment.router.openReport(.cashFlow) }
                        .keyboardShortcut("1", modifiers: [.command, .option, .shift])
                    if environment.companyContext?.isInventoryEnabled == true {
                        Button("Stock Ageing") { environment.router.openReport(.stockAgeing) }
                            .keyboardShortcut("2", modifiers: [.command, .option, .shift])
                    }
                }
            }
        }
    }
}

/// Menu button for a global-shortcut action in `AppActionRegistry`.
@ViewBuilder
private func actionButton(_ id: AppActionID, environment: AppEnvironment) -> some View {
    if let action = AppActionRegistry.action(for: id) {
        let button = Button(action.title) {
            AppActionRegistry.perform(id, router: environment.router)
        }
        if let key = action.key {
            button.keyboardShortcut(key, modifiers: action.modifiers)
        } else {
            button
        }
    }
}

/// Voucher menu button: registry title plus its function-key label, matching
/// the menu's original "Contra (F4)"-style wording.
@ViewBuilder
private func voucherActionButton(_ type: VoucherType.Code, environment: AppEnvironment) -> some View {
    if let action = AppActionRegistry.action(for: .voucherCreate(type)) {
        let label = action.shortcutLabel.map { "\(action.title) (\($0))" } ?? action.title
        Button(label) {
            AppActionRegistry.perform(.voucherCreate(type), router: environment.router)
        }
    }
}

extension Notification.Name {
    public static let aveloRequestNewCompany = Notification.Name("avelo.request.newCompany")
    public static let aveloRequestOpenCompany = Notification.Name("avelo.request.openCompany")
    public static let aveloRequestBackup = Notification.Name("avelo.request.backup")
    public static let aveloRequestRestore = Notification.Name("avelo.request.restore")
    public static let aveloRequestPreferences = Notification.Name("avelo.request.preferences")
    public static let aveloRequestCloseCompany = Notification.Name("avelo.request.closeCompany")
    public static let aveloRequestCloseFy = Notification.Name("avelo.request.closeFy")
    public static let aveloRequestLockFy = Notification.Name("avelo.request.lockFy")
}
