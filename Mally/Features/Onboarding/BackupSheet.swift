import SwiftUI

public struct BackupSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var status: String = ""
    @State private var isWorking: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup").font(.title2.bold())
            Text("Save a snapshot of the current company database. The backup is portable and can be restored on any Mac running Mally.")
                .foregroundStyle(.secondary)
            HStack {
                if isWorking { ProgressView() }
                Button("Create Backup…") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || env.companyContext == nil)
            }
            if !status.isEmpty {
                StatusBadge(kind: .info, text: status)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Close") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 260)
    }

    private func run() {
        guard let ctx = env.companyContext else { return }
        isWorking = true
        status = ""
        Task {
            defer { isWorking = false }
            do {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "MallyBackup-\(ctx.companyId.uuidString.prefix(8)).zip"
                panel.canCreateDirectories = true
                let result = await NSPanelBridge.runSave(panel)
                if result == .OK, let url = panel.url {
                    _ = try await env.backupService.export(companyId: ctx.companyId, companyName: ctx.companyName, to: url)
                    status = "Backup saved to \(url.lastPathComponent)."
                    env.showSuccess(status)
                }
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }
}

extension NSPanelBridge {
    @MainActor
    static func runSave(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { resp in cont.resume(returning: resp) }
        }
    }
}
