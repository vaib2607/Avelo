import SwiftUI
import AppKit

public struct RestoreSheet: View {

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @State private var status: String = ""
    @State private var isWorking: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Backup").font(.title2.bold())
            Text("Choose a Mally backup .zip file. A new company is created from its contents; your existing data is not modified.")
                .foregroundStyle(.secondary)
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
        Task {
            defer { isWorking = false }
            do {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                let result = await panel.beginAsync()
                if result == .OK, let url = panel.url {
                    let restore = RestoreService(manager: env.manager)
                    let newId = try await restore.restore(from: url)
                    env.showSuccess("Restored as new company.")
                    status = "New company id: \(newId.uuidString.prefix(8))"
                }
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }
}

extension NSOpenPanel {
    @MainActor
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            self.begin { resp in cont.resume(returning: resp) }
        }
    }
}
