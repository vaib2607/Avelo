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
                CommandMenu("Go") {
                    Button("Dashboard") { environment.router.go(.dashboard) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("Accounts")  { environment.router.go(.accounts) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("Vouchers")  { environment.router.go(.vouchers) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("Reports")   { environment.router.go(.reports) }
                        .keyboardShortcut("4", modifiers: .command)
                    Button("Inventory") { environment.router.go(.inventory) }
                        .keyboardShortcut("5", modifiers: .command)
                    Button("Payroll")   { environment.router.go(.payroll) }
                        .keyboardShortcut("6", modifiers: .command)
                    Button("Banking")   { environment.router.go(.banking) }
                        .keyboardShortcut("7", modifiers: .command)
                    Button("Audit")     { environment.router.go(.audit) }
                        .keyboardShortcut("8", modifiers: .command)
                    Button("Settings")  { environment.router.go(.settings) }
                        .keyboardShortcut("9", modifiers: .command)
                }
                CommandMenu("Voucher") {
                    Button("Contra (F4)")     { environment.router.present(.newContra) }
                    Button("Payment (F5)")    { environment.router.present(.newPayment) }
                    Button("Receipt (F6)")    { environment.router.present(.newReceipt) }
                    Button("Journal (F7)")    { environment.router.present(.newJournal) }
                    Button("Sales (F8)")      { environment.router.present(.newSales) }
                    Button("Purchase (F9)")   { environment.router.present(.newPurchase) }
                    Button("Credit Note (F10)") { environment.router.present(.newCreditNote) }
                    Button("Debit Note (F11)")  { environment.router.present(.newDebitNote) }
                }
            }
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
