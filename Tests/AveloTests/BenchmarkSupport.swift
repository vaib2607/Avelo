import Foundation
import Darwin.Mach

enum BenchmarkConfig {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["AVELO_BENCHMARK"] == "1"
    }

    static var millionEnabled: Bool {
        ProcessInfo.processInfo.environment["AVELO_BENCHMARK_MILLION"] == "1"
    }

    static var millionBatchedEnabled: Bool {
        ProcessInfo.processInfo.environment["AVELO_BENCHMARK_MILLION_BATCHED"] == "1"
    }

    static var millionVoucherCount: Int {
        min(Int(ProcessInfo.processInfo.environment["AVELO_BENCHMARK_MILLION_COUNT"] ?? "") ?? maxStressVoucherCount, maxStressVoucherCount)
    }

    static var millionProgressStep: Int {
        Int(ProcessInfo.processInfo.environment["AVELO_BENCHMARK_MILLION_PROGRESS_STEP"] ?? "") ?? 10_000
    }

    static var maxStressVoucherCount: Int { 500_000 }

    static var scorecardKind: String {
        ProcessInfo.processInfo.environment["AVELO_BENCHMARK_SCORECARD"] ?? "before"
    }
}

struct BenchmarkResult: Sendable {
    let name: String
    let durationNanoseconds: UInt64
    let durationSeconds: Double
    let residentBytes: UInt64
    let thermalState: ProcessInfo.ThermalState
}

enum BenchmarkClock {
    static func measure(_ name: String, _ block: () throws -> Void) rethrows -> BenchmarkResult {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsed = end - start
        return BenchmarkResult(
            name: name,
            durationNanoseconds: elapsed,
            durationSeconds: Double(elapsed) / 1_000_000_000,
            residentBytes: Self.currentResidentBytes(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    static func measureAsync(_ name: String, _ block: () async throws -> Void) async rethrows -> BenchmarkResult {
        let start = DispatchTime.now().uptimeNanoseconds
        try await block()
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsed = end - start
        return BenchmarkResult(
            name: name,
            durationNanoseconds: elapsed,
            durationSeconds: Double(elapsed) / 1_000_000_000,
            residentBytes: Self.currentResidentBytes(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    static func emit(_ result: BenchmarkResult) {
        print("BENCHMARK \(result.name): \(String(format: "%.3f", result.durationSeconds))s resident=\(result.residentBytes) thermal=\(result.thermalState.rawValue)")
    }
}
