import SwiftUI
import AppKit

public struct RestoreSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var status: String = ""
    @State private var isWorking: Bool = false
    @State private var recoveryKey: String = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Backup").font(.title2.bold())
            Text("Choose a Avelo `.avelobackup` file. A new company is created from its contents; your existing data is not modified.")
                .foregroundStyle(.secondary)
            TextField("Recovery key for encrypted backups", text: $recoveryKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                if isWorking { ProgressView() }
                Button("Choose File…") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
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
        .frame(minWidth: 480, minHeight: 260)
    }

    private func run() {
        isWorking = true
        status = ""
        Task<Void, Never> {
            defer { isWorking = false }
            do {
                let trimmedRecoveryKey = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let suppliedRecoveryKey: String?
                if trimmedRecoveryKey.isEmpty {
                    suppliedRecoveryKey = nil
                } else {
                    let canonicalRecoveryKey = try RecoveryKeyCodec.canonicalize(trimmedRecoveryKey)
                    recoveryKey = canonicalRecoveryKey
                    suppliedRecoveryKey = canonicalRecoveryKey
                }

                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                let result = await NSPanelBridge.runOpen(panel)
                if result == .OK, let url = panel.url {
                    let restore = RestoreService(manager: env.manager)
<<<<<<< HEAD:Avelo/Features/Onboarding/RestoreSheet.swift
                    let restored = try await restore.restore(from: url, recoveryKey: suppliedRecoveryKey)
=======
                    let restored = try await restore.restore(from: url)
>>>>>>> origin/main:Mally/Features/Onboarding/RestoreSheet.swift
                    await env.openCompany(restored.id)
                    env.notifyDataChanged()
                    env.showSuccess("Restored as new company.")
                    status = "Opened restored company \(restored.name)."
                    router.presentedSheet = nil
                }
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }
}

enum NSPanelBridge {
    @MainActor
    static func runOpen(_ panel: NSOpenPanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { resp in cont.resume(returning: resp) }
        }
    }
}
