import XCTest
@testable import Avelo

final class BenchmarkSuiteTests: XCTestCase {
    private let suite = BenchmarkSuite()

    private func voucherDate(offsetDays: Int) -> String {
        let start = DateFormatters.parseDate("2024-04-01")!
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: start)!
        return DateFormatters.formatIsoDate(date)
    }

    private func makeRealisticFixture(vouchers: Int) throws -> (TestCompany, URL) {
        let (tc, cleanupURL) = try TestCompany.makeOnDisk(name: "Benchmark Co")
        let service = VoucherService(db: tc.db, companyId: tc.companyId)
        let patterns: [[VoucherDraft.Line]] = [
            [tc.line(tc.cashId, 1_500, .debit), tc.line(tc.salesId, 1_500, .credit)],
            [tc.line(tc.rentId, 1_250, .debit), tc.line(tc.cashId, 1_250, .credit)],
            [tc.line(tc.cashId, 2_100, .debit), tc.line(tc.salesId, 2_100, .credit)]
        ]
        for i in 0..<vouchers {
            let pattern = patterns[i % patterns.count]
            _ = try service.post(
                draft: tc.draft(
                    on: voucherDate(offsetDays: i % 365),
                    narration: "Benchmark \(i)",
                    lines: pattern
                ),
                in: tc.fy
            )
        }
        return (tc, cleanupURL)
    }

    private func makeManagedFixture() async throws -> (manager: DatabaseManager, companyId: UUID, companyName: String, rootURL: URL) {
<<<<<<< HEAD
        let root = BenchmarkConfig.temporaryDirectory
            .appendingPathComponent("avelo-benchmark-managed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try DatabaseManager(appSupportDirectory: root, keyStore: InMemoryCompanyKeyStore())
        let companyId = UUID()
        let companyName = "Managed Benchmark Co"
        let companyURL = try await manager.createCompanyFile(companyId: companyId)
        let key = try XCTUnwrap(try manager.keyStore.retrieve(companyId: companyId))
        let db = try SQLiteDatabase(path: companyURL.path, key: key)
=======
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("avelo-benchmark-managed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try DatabaseManager(appSupportDirectory: root)
        let companyId = UUID()
        let companyName = "Managed Benchmark Co"
        let companyURL = try await manager.createCompanyFile(companyId: companyId)
        let db = try SQLiteDatabase(path: companyURL.path)
>>>>>>> origin/main
        defer { db.close() }
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: companyName)
        let entry = CompanyRegistryEntry(
            id: companyId,
            name: companyName,
            sqliteFileName: companyURL.lastPathComponent,
            lastOpenedAt: nil,
            createdAt: Date()
        )
        try await manager.registerCompany(entry)
        return (manager, companyId, companyName, root)
    }

    private func logBenchmarkProgress(name: String, completed: Int, total: Int, startedAt: Date) {
        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
        let completedFraction = total > 0 ? Double(completed) / Double(total) : 0
        let remaining = max(total - completed, 0)
        let rate = Double(completed) / elapsed
        let eta = rate > 0 ? Double(remaining) / rate : 0
        print(
            "BENCHMARK \(name): \(completed)/\(total) (\(String(format: "%.1f", completedFraction * 100.0))%) elapsed=\(String(format: "%.1f", elapsed))s eta=\(String(format: "%.1f", eta))s"
        )
        fflush(stdout)
    }

    func testBenchmarkCoreWorkflowSuite() throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Benchmark suite disabled; set AVELO_BENCHMARK=1.")

        let fixture = try BenchmarkClock.measure("fixture_25k") {
            let (tc, cleanupURL) = try makeRealisticFixture(vouchers: 25_000)
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        suite.record(fixture)
        BenchmarkClock.emit(fixture)

        let (tc, cleanupURL) = try makeRealisticFixture(vouchers: 5_000)
        defer {
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        let voucherService = VoucherService(db: tc.db, companyId: tc.companyId)
        let reportService = ReportService(db: tc.db, companyId: tc.companyId)

        let post = try BenchmarkClock.measure("post_500") {
            for i in 0..<500 {
                _ = try voucherService.post(
                    draft: tc.draft(
                        on: voucherDate(offsetDays: i % 365),
                        narration: "Post \(i)",
                        lines: [
                            tc.line(tc.cashId, 1_000 + Int64(i % 47), .debit),
                            tc.line(tc.salesId, 1_000 + Int64(i % 47), .credit)
                        ]
                    ),
                    in: tc.fy
                )
            }
        }
        suite.record(post)
        BenchmarkClock.emit(post)

        let reports = try BenchmarkClock.measure("reports_bundle") {
            let asOf = DateFormatters.parseDate("2024-08-31")!
            let from = DateFormatters.parseDate("2024-04-01")!
            _ = try reportService.trialBalance(asOfDate: asOf, financialYearId: tc.fy.id)
            _ = try reportService.profitAndLoss(fromDate: from, toDate: asOf, financialYearId: tc.fy.id)
            _ = try reportService.balanceSheet(asOfDate: asOf, financialYearId: tc.fy.id)
            _ = try reportService.ledger(accountId: tc.cashId, financialYearId: tc.fy.id, fromDate: from, toDate: asOf)
            _ = try reportService.dayBook(fromDate: from, toDate: asOf)
            _ = try reportService.outstanding(asOfDate: asOf, direction: .both)
            _ = try reportService.gstSummary(fromDate: from, toDate: asOf)
        }
        suite.record(reports)
        BenchmarkClock.emit(reports)

        let totals = try tc.db.queryOne(
            """
            SELECT
              COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END), 0) AS dr,
              COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END), 0) AS cr,
              COUNT(DISTINCT voucher_id) AS voucher_count
            FROM avelo_ledger_lines
            """
        ) { ($0.int("dr"), $0.int("cr"), $0.int("voucher_count")) }

        XCTAssertEqual(totals?.0, totals?.1)
        XCTAssertEqual(totals?.2, 5_500)
        suite.sampleResources("core_after_reports")
        try suite.writeScorecard(kind: BenchmarkConfig.scorecardKind)
    }

    func testMillionVoucherStressSuite() throws {
        try XCTSkipUnless(BenchmarkConfig.millionEnabled, "Million-voucher benchmark disabled; set AVELO_BENCHMARK_MILLION=1.")

        try autoreleasepool {
            let (tc, cleanupURL) = try TestCompany.makeOnDisk(name: "Million Co")
            defer {
                tc.db.close()
                try? FileManager.default.removeItem(at: cleanupURL)
            }
            let service = VoucherService(db: tc.db, companyId: tc.companyId)
            let reportService = ReportService(db: tc.db, companyId: tc.companyId)
            let startedAt = Date()
            let batched = BenchmarkConfig.millionBatchedEnabled
            let totalCount = BenchmarkConfig.millionVoucherCount
            let progressStep = max(BenchmarkConfig.millionProgressStep, 1)

            let benchmarkName = batched ? "million_voucher_post_batched" : "million_voucher_post"

            let total = try BenchmarkClock.measure(benchmarkName) {
                var pending: [VoucherDraft] = []
                pending.reserveCapacity(1_000)
                func makeDraft(_ i: Int) -> VoucherDraft {
                    let amount = Int64(1_000 + (i % 97) * 25)
                    let lines: [VoucherDraft.Line]
                    if i.isMultiple(of: 2) {
                        lines = [
                            tc.line(tc.cashId, amount, .debit),
                            tc.line(tc.salesId, amount, .credit)
                        ]
                    } else {
                        lines = [
                            tc.line(tc.rentId, amount, .debit),
                            tc.line(tc.cashId, amount, .credit)
                        ]
                    }
                    return tc.draft(on: self.voucherDate(offsetDays: i % 365), narration: "Million \(i)", lines: lines)
                }
                if batched {
                    for i in 0..<totalCount {
                        pending.append(makeDraft(i))
                        let completed = i + 1
                        if pending.count == 1_000 || completed == totalCount {
                            _ = try service.postBatch(pending, in: tc.fy)
                            pending.removeAll(keepingCapacity: false)
                        }
                        if completed == 1 || completed.isMultiple(of: progressStep) || completed == totalCount {
                            self.suite.sampleResources("stress_progress_\(completed)")
                            self.logBenchmarkProgress(
                                name: benchmarkName,
                                completed: completed,
                                total: totalCount,
                                startedAt: startedAt
                            )
                        }
                    }
                } else {
                    for i in 0..<totalCount {
                        _ = try service.post(draft: makeDraft(i), in: tc.fy)
                        let completed = i + 1
                        if completed == 1 || completed.isMultiple(of: progressStep) || completed == totalCount {
                            self.suite.sampleResources("stress_progress_\(completed)")
                            self.logBenchmarkProgress(
                                name: benchmarkName,
                                completed: completed,
                                total: totalCount,
                                startedAt: startedAt
                            )
                        }
                    }
                }
            }
            suite.record(total)
            BenchmarkClock.emit(total)

            let reports = try BenchmarkClock.measure("million_report_pass") {
                let asOf = DateFormatters.parseDate("2024-08-31")!
                _ = try reportService.trialBalance(asOfDate: asOf, financialYearId: tc.fy.id)
                _ = try reportService.balanceSheet(asOfDate: asOf, financialYearId: tc.fy.id)
                _ = try reportService.profitAndLoss(fromDate: DateFormatters.parseDate("2024-04-01")!, toDate: asOf, financialYearId: tc.fy.id)
            }
            suite.record(reports)
            BenchmarkClock.emit(reports)

            let totals = try tc.db.queryOne(
                """
                SELECT
                  COALESCE(SUM(CASE WHEN side='debit' THEN amount_paise ELSE 0 END), 0) AS dr,
                  COALESCE(SUM(CASE WHEN side='credit' THEN amount_paise ELSE 0 END), 0) AS cr,
                  COUNT(DISTINCT voucher_id) AS voucher_count
                FROM avelo_ledger_lines
                """
            ) { ($0.int("dr"), $0.int("cr"), $0.int("voucher_count")) }

            XCTAssertEqual(totals?.0, totals?.1)
            XCTAssertEqual(totals?.2, Int64(totalCount))
            ReportService.invalidateCache(companyId: tc.companyId)
            tc.db.close()
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        BenchmarkSuite.releaseMemoryPressure()
        suite.sampleResources("stress_post_cleanup")
        try suite.writeScorecard(kind: BenchmarkConfig.scorecardKind)
    }

    func testBenchmarkBackupRestoreSuite() async throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Benchmark suite disabled; set AVELO_BENCHMARK=1.")

        let (manager, companyId, companyName, rootURL) = try await makeManagedFixture()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let backupService = BackupService(manager: manager)
        let sourceURL = try await manager.companyFileURL(id: companyId)
        let backupURL = rootURL.appendingPathComponent("backup.avelobackup")
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.appendingPathExtension("manifest.json"))
        }

        let export = try await BenchmarkClock.measureAsync("backup_export") {
            _ = try await backupService.export(companyId: companyId, companyName: companyName, to: backupURL)
        }
        suite.record(export)
        BenchmarkClock.emit(export)

        let restoreRoot = rootURL.appendingPathComponent("restore", isDirectory: true)
        try FileManager.default.createDirectory(at: restoreRoot, withIntermediateDirectories: true)
<<<<<<< HEAD
        let restoreManager = try DatabaseManager(appSupportDirectory: restoreRoot, keyStore: InMemoryCompanyKeyStore())
=======
        let restoreManager = try DatabaseManager(appSupportDirectory: restoreRoot)
>>>>>>> origin/main
        defer { try? FileManager.default.removeItem(at: restoreRoot) }
        let restoreService = RestoreService(manager: restoreManager)

        let restore = try await BenchmarkClock.measureAsync("backup_restore") {
<<<<<<< HEAD
            _ = try await restoreService.restore(from: backupURL, recoveryKey: try manager.recoveryKey(for: companyId))
=======
            _ = try await restoreService.restore(from: backupURL)
>>>>>>> origin/main
        }
        suite.record(restore)
        BenchmarkClock.emit(restore)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        suite.sampleResources("backup_restore_complete")
        try suite.writeScorecard(kind: BenchmarkConfig.scorecardKind)
    }

    func testBenchmarkLaunchAndCompanySwitchSuite() async throws {
        try XCTSkipUnless(BenchmarkConfig.enabled, "Benchmark suite disabled; set AVELO_BENCHMARK=1.")

        let fixtureA = try await makeManagedFixture()
        let fixtureB = try await makeManagedFixture()
        defer {
            try? FileManager.default.removeItem(at: fixtureA.rootURL)
            try? FileManager.default.removeItem(at: fixtureB.rootURL)
        }

        let launch = await BenchmarkClock.measureAsync("cold_launch_first_interactive_frame") {
            let _ = await MainActor.run { AppRouter() }
        }
        suite.record(launch)
        BenchmarkClock.emit(launch)

        let gui = await BenchmarkClock.measureAsync("gui_shell_latency") {
            await MainActor.run {
                let router = AppRouter()
                router.selection = .vouchers
                router.selection = .reports
            }
        }
        suite.record(gui)
        BenchmarkClock.emit(gui)

        for i in 0..<3 {
            let open = try await BenchmarkClock.measureAsync("company_open_\(i + 1)") {
                _ = try await fixtureA.manager.openCompany(id: fixtureA.companyId)
            }
            suite.record(open)
            BenchmarkClock.emit(open)

            let switchMetric = try await BenchmarkClock.measureAsync("company_switch_\(i + 1)") {
                await fixtureA.manager.closeCompany(id: fixtureA.companyId)
                _ = try await fixtureB.manager.openCompany(id: fixtureB.companyId)
                await fixtureB.manager.closeCompany(id: fixtureB.companyId)
            }
            suite.record(switchMetric)
            BenchmarkClock.emit(switchMetric)

            let close = await BenchmarkClock.measureAsync("company_close_\(i + 1)") {
                await fixtureA.manager.closeCompany(id: fixtureA.companyId)
            }
            suite.record(close)
            BenchmarkClock.emit(close)
        }

        suite.sampleResources("launch_switch_complete")
        try suite.writeScorecard(kind: BenchmarkConfig.scorecardKind)
    }
}
