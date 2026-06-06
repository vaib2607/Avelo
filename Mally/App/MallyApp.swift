import SwiftUI

@main
struct MallyApp: App {

    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.router)
                .frame(minWidth: 1080, minHeight: 720)
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
