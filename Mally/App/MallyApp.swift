import SwiftUI
import AppKit

@main
struct MallyApp: App {

    @StateObject private var environment = AppEnvironment()
    @StateObject private var keyboardBridge = KeyboardBridge()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.router)
                .environmentObject(keyboardBridge)
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
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Company…") {
                    NotificationCenter.default.post(name: .mallyRequestNewCompany, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Backup…") {
                    NotificationCenter.default.post(name: .mallyRequestBackup, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
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

extension Notification.Name {
    public static let mallyRequestNewCompany = Notification.Name("mally.request.newCompany")
    public static let mallyRequestBackup = Notification.Name("mally.request.backup")
    public static let mallyRequestRestore = Notification.Name("mally.request.restore")
    public static let mallyRequestCloseFy = Notification.Name("mally.request.closeFy")
    public static let mallyRequestLockFy = Notification.Name("mally.request.lockFy")
}
