import XCTest
@testable import Avelo

final class PerformanceBenchmarkTests: XCTestCase {
    private let tenThousandBaselineSeconds = 7.858
    private let hundredThousandBaselineSeconds = 92.505
    private let allowedRegressionMultiplier = 1.15

    private func voucherDate(offsetDays: Int) -> String {
        let start = DateFormatters.parseDate("2024-04-01")!
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: start)!
        return DateFormatters.formatIsoDate(date)
    }

    private func makeEncryptedFixture(name: String = "Encrypted Benchmark Co") throws -> (fixture: TestCompany, cleanupURL: URL) {
        let root = BenchmarkConfig.temporaryDirectory
            .appendingPathComponent("avelo-encrypted-benchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("company.sqlite")
        let key = Data((0..<32).map { UInt8($0 + 1) })
        let db = try SQLiteDatabase(path: dbURL.path, key: key)
        try MigrationRunner().runMigrations(on: db)
        let fixture = try TestCompany.seed(into: db, companyId: UUID(), companyName: name)
        return (fixture, root)
    }

    private func makeDrafts(_ count: Int, fixture tc: TestCompany) -> [VoucherDraft] {
        (0..<count).map { i in
            let amount = Int64(1_000 + (i % 97) * 25)
            let lines: [VoucherDraft.Line] = i.isMultiple(of: 2)
                ? [tc.line(tc.cashId, amount, .debit), tc.line(tc.salesId, amount, .credit)]
                : [tc.line(tc.rentId, amount, .debit), tc.line(tc.cashId, amount, .credit)]
            return tc.draft(
                on: voucherDate(offsetDays: i % 365),
                narration: "Encrypted benchmark \(i)",
                lines: lines
            )
        }
    }

    private func assertVoucherCount(_ expected: Int64, db: SQLiteDatabase) throws {
        let count = try db.queryOne("SELECT COUNT(*) FROM avelo_vouchers") { $0.int(0) }
        XCTAssertEqual(count, expected)
    }

    private func assertWithinThreshold(_ result: BenchmarkResult, baseline: Double, file: StaticString = #filePath, line: UInt = #line) {
        let threshold = baseline * allowedRegressionMultiplier
        BenchmarkClock.emit(result)
        XCTAssertLessThanOrEqual(
            result.durationSeconds,
            threshold,
            "\(result.name) took \(String(format: "%.3f", result.durationSeconds))s; threshold is \(String(format: "%.3f", threshold))s from baseline \(baseline)s.",
            file: file,
            line: line
        )
    }

    func testEncryptedPostBatchTenThousandBenchmark() throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Set AVELO_BENCHMARK=1 to run encryption-aware performance benchmarks.")
        let (tc, cleanupURL) = try makeEncryptedFixture()
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        let journalMode = try tc.db.queryOne("PRAGMA journal_mode") { $0.text(0).lowercased() }
        XCTAssertEqual(journalMode, "wal")

        let drafts = makeDrafts(10_000, fixture: tc)
        let result = try BenchmarkClock.measure("encrypted_postBatch_10k") {
            _ = try VoucherService(db: tc.db, companyId: tc.companyId).postBatch(drafts, in: tc.fy)
        }
        try assertVoucherCount(10_000, db: tc.db)
        assertWithinThreshold(result, baseline: tenThousandBaselineSeconds)
    }

    func testEncryptedPostBatchHundredThousandBenchmark() throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Set AVELO_BENCHMARK=1 to run encryption-aware performance benchmarks.")
        let (tc, cleanupURL) = try makeEncryptedFixture()
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }

        let drafts = makeDrafts(100_000, fixture: tc)
        let result = try BenchmarkClock.measure("encrypted_postBatch_100k") {
            _ = try VoucherService(db: tc.db, companyId: tc.companyId).postBatch(drafts, in: tc.fy)
        }
        try assertVoucherCount(100_000, db: tc.db)
        assertWithinThreshold(result, baseline: hundredThousandBaselineSeconds)
    }

    func testEncryptedPostBatchFailureCommitsOnlyCompletedChunks() throws {
        let (tc, cleanupURL) = try makeEncryptedFixture()
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        var drafts = makeDrafts(1_200, fixture: tc)
        drafts[500] = tc.draft(
            on: voucherDate(offsetDays: 1),
            narration: "Invalid chunk 2",
            lines: [
                VoucherDraft.Line(accountId: nil, amountPaise: 1_000, side: .debit),
                tc.line(tc.salesId, 1_000, .credit)
            ]
        )

        XCTAssertThrowsError(try VoucherService(db: tc.db, companyId: tc.companyId).postBatch(drafts, in: tc.fy))
        try assertVoucherCount(500, db: tc.db)
        let laterRows = try tc.db.queryOne(
            "SELECT COUNT(*) FROM avelo_vouchers WHERE narration IN ('Encrypted benchmark 500', 'Encrypted benchmark 999', 'Encrypted benchmark 1000')"
        ) { $0.int(0) }
        XCTAssertEqual(laterRows, 0)
    }

    @MainActor
    func testAccountTreeReloadLargeChartBenchmark() async throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Set AVELO_BENCHMARK=1 to run encryption-aware performance benchmarks.")
        let (tc, cleanupURL) = try makeEncryptedFixture()
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        let accountService = AccountService(db: tc.db, companyId: tc.companyId)
        for index in 0..<500 {
            _ = try accountService.createAccount(.init(
                code: "L\(String(format: "%03d", index))",
                name: "Benchmark Ledger \(index)",
                groupId: index.isMultiple(of: 2) ? tc.assetsGroupId : tc.expenseGroupId,
                openingBalancePaise: 0,
                openingBalanceSide: .debit,
                gstin: nil,
                existingAccountId: nil
            ))
        }

        let cache = AccountTreeCache(companyId: tc.companyId, database: tc.db, financialYearId: tc.fy.id)
        let result = await BenchmarkClock.measureAsync("account_tree_reload_500_ledgers") {
            await cache.reload()
        }
        BenchmarkClock.emit(result)
        XCTAssertNil(cache.lastError)
        XCTAssertGreaterThanOrEqual(cache.current()?.allLedgers.count ?? 0, 500)
        XCTAssertLessThanOrEqual(result.durationSeconds, 2.0)
    }

    func testEncryptedReportsFiftyThousandVoucherBenchmark() throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Set AVELO_BENCHMARK=1 to run encryption-aware performance benchmarks.")
        let (tc, cleanupURL) = try makeEncryptedFixture()
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        _ = try VoucherService(db: tc.db, companyId: tc.companyId).postBatch(makeDrafts(50_000, fixture: tc), in: tc.fy)
        let service = ReportService(db: tc.db, companyId: tc.companyId)
        let from = DateFormatters.parseDate("2024-04-01")!
        let asOf = DateFormatters.parseDate("2025-03-31")!
        let reports: [(String, () throws -> Void, Double)] = [
            ("report_trialBalance_50k", { _ = try service.trialBalance(asOfDate: asOf, financialYearId: tc.fy.id) }, 8.0),
            ("report_profitAndLoss_50k", { _ = try service.profitAndLoss(fromDate: from, toDate: asOf, financialYearId: tc.fy.id) }, 8.0),
            ("report_balanceSheet_50k", { _ = try service.balanceSheet(asOfDate: asOf, financialYearId: tc.fy.id) }, 8.0),
            ("report_gstSummary_50k", { _ = try service.gstSummary(fromDate: from, toDate: asOf) }, 4.0),
            ("report_cashFlow_50k", { _ = try service.cashFlow(fromDate: from, toDate: asOf) }, 8.0),
            ("report_stockAgeing_50k", { _ = try service.stockAgeing(asOfDate: asOf) }, 2.0)
        ]

        for (name, block, threshold) in reports {
            ReportService.invalidateCache(companyId: tc.companyId)
            let result = try BenchmarkClock.measure(name, block)
            BenchmarkClock.emit(result)
            XCTAssertLessThanOrEqual(result.durationSeconds, threshold, "\(name) exceeded documented threshold \(threshold)s.")
        }
    }
}
