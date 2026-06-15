import Foundation
import Darwin
import Darwin.Mach
@testable import Avelo

struct BenchmarkMetric: Codable, Sendable {
    let name: String
    let durationNanoseconds: UInt64
    let durationSeconds: Double
    let residentMegabytes: Double
    let thermalState: Int
}

struct BenchmarkResourceSample: Codable, Sendable {
    let name: String
    let timestamp: Date
    let residentMegabytes: Double
    let userCPUSeconds: Double
    let systemCPUSeconds: Double
    let thermalState: Int
}

struct BenchmarkScorecard: Codable, Sendable {
    let generatedAt: Date
    let maxStressVouchers: Int
    var metrics: [BenchmarkMetric]
    var samples: [BenchmarkResourceSample]
}

final class BenchmarkSuite {
    private(set) var scorecard = BenchmarkScorecard(
        generatedAt: Date(),
        maxStressVouchers: BenchmarkConfig.maxStressVoucherCount,
        metrics: [],
        samples: []
    )

    func record(_ result: BenchmarkResult) {
        scorecard.metrics.append(
            BenchmarkMetric(
                name: result.name,
                durationNanoseconds: result.durationNanoseconds,
                durationSeconds: result.durationSeconds,
                residentMegabytes: Double(result.residentBytes) / 1_048_576.0,
                thermalState: result.thermalState.rawValue
            )
        )
    }

    func sampleResources(_ name: String) {
        scorecard.samples.append(Self.resourceSample(name))
    }

    func writeScorecard(kind: String) throws {
        let outputDirectory = BenchmarkConfig.outputDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent("avelo_bench_\(kind).json")
        var output = scorecard
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let existing = try? decoder.decode(BenchmarkScorecard.self, from: data) {
                let names = Set(output.metrics.map(\.name))
                output.metrics = existing.metrics.filter { !names.contains($0.name) } + output.metrics
                output.samples = existing.samples + output.samples
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(output).write(to: url, options: .atomic)
    }

    static func resourceSample(_ name: String) -> BenchmarkResourceSample {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000.0
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000.0
        return BenchmarkResourceSample(
            name: name,
            timestamp: Date(),
            residentMegabytes: Double(BenchmarkClock.currentResidentBytes()) / 1_048_576.0,
            userCPUSeconds: user,
            systemCPUSeconds: system,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue
        )
    }

    static func releaseMemoryPressure() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
