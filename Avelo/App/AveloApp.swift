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

                    Button("Inventory Settings…") {
                        environment.router.present(.manageInventory)
                    }

                    Button("Payroll Settings…") {
                        environment.router.present(.managePayroll)
                    }

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
                CommandMenu("Modules") {
                    Button("Inventory") { environment.router.go(.inventory) }
                        .keyboardShortcut("5", modifiers: [.command, .shift])
                    Button("GST") { environment.router.go(.gst) }
                        .keyboardShortcut("6", modifiers: [.command, .shift])
                    Button("Payroll") { environment.router.go(.payroll) }
                        .keyboardShortcut("7", modifiers: [.command, .shift])
                    Button("Banking") { environment.router.go(.banking) }
                        .keyboardShortcut("8", modifiers: [.command, .shift])
                    Button("Audit") { environment.router.go(.audit) }
                        .keyboardShortcut("9", modifiers: [.command, .shift])
                    Button("Settings") { environment.router.go(.settings) }
                        .keyboardShortcut("0", modifiers: [.command, .shift])
                }
                CommandMenu("Masters") {
                    Button("New Account…") { environment.router.present(.newAccount) }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    Button("New Item…") { environment.router.present(.newItem) }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                    Button("New Employee…") { environment.router.present(.newEmployee) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("New Financial Year…") { environment.router.present(.newFinancialYear) }
                        .keyboardShortcut("y", modifiers: [.command, .shift])
                }
                CommandMenu("Voucher") {
                    Button("Contra (F4)")     { environment.router.present(.newContra) }
                    Button("Payment (F5)")    { environment.router.present(.newPayment) }
                    Button("Receipt (F6)")    { environment.router.present(.newReceipt) }
                    Button("Journal (F7)")    { environment.router.present(.newJournal) }
                    Button("Memo")            { environment.router.present(.newJournal) }
                    Button("Sales (F8)")      { environment.router.present(.newSales) }
                    Button("Purchase (F9)")   { environment.router.present(.newPurchase) }
                    Button("Credit Note") { environment.router.present(.newCreditNote) }
                    Button("Debit Note")  { environment.router.present(.newDebitNote) }
                    Button("Purchase Order") { environment.router.present(.newPurchaseOrder) }
                    Button("Sales Order") { environment.router.present(.newSalesOrder) }
                    Button("Receipt Note") { environment.router.present(.newReceiptNote) }
                    Button("Delivery Note") { environment.router.present(.newDeliveryNote) }
                    Button("Physical Stock") { environment.router.present(.newPhysicalStock) }
                    Button("Stock Journal") { environment.router.present(.newStockJournal) }
                    Button("Rejection In") { environment.router.present(.newRejectionIn) }
                    Button("Rejection Out") { environment.router.present(.newRejectionOut) }
                }
                CommandMenu("Reports") {
                    Button("Trial Balance") { environment.router.openReport(.trialBalance) }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("Profit & Loss") { environment.router.openReport(.profitLoss) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("Balance Sheet") { environment.router.openReport(.balanceSheet) }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                    Button("GST Summary") { environment.router.openReport(.gstSummary) }
                        .keyboardShortcut("4", modifiers: [.command, .option])
                    Button("Day Book") { environment.router.openReport(.dayBook) }
                        .keyboardShortcut("5", modifiers: [.command, .option])
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
                    Button("Stock Summary") { environment.router.openReport(.stockValuation) }
                    Button("Stock Movement") { environment.router.openReport(.stockMovement) }
                    Button("Stock Register") { environment.router.openReport(.stockRegister) }
                    Button("GST Filing Views") { environment.router.openReport(.gstFiling) }
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
