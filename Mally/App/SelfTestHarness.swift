import Foundation
import Darwin

enum SelfTestHarness {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--self-test")
    }

    static var outputPath: String? {
        if let envPath = ProcessInfo.processInfo.environment["MALLY_SELFTEST_OUTPUT"], !envPath.isEmpty {
            return envPath
        }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--self-test-output"), args.indices.contains(args.index(after: idx)) {
            return args[args.index(after: idx)]
        }
        return nil
    }

    @MainActor
    static func runAndExit() async -> Never {
        let exitCode: Int32
        do {
            let summary = try await LocalRCFlowRunner.run()
            let message = [
                "SELFTEST OK",
                "Company: \(summary.companyName)",
                "Created account: \(summary.createdAccountCode)",
                "Trial balance balanced: \(summary.trialBalanceBalanced)",
                "Restored trial balance balanced: \(summary.restoredTrialBalanceBalanced)"
            ].joined(separator: "\n")
            try write(message + "\n")
            exitCode = 0
        } catch {
            FileHandle.standardError.write(Data(("SELFTEST FAILED: \(error)\n").utf8))
            exitCode = 1
        }

        Darwin.exit(exitCode)
    }

    private static func write(_ text: String) throws {
        FileHandle.standardOutput.write(Data(text.utf8))
        if let outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
