import XCTest
@testable import Mally

final class RestoreServiceTests: XCTestCase {

    func testPrepareRestoredCompanyDatabaseRemapsCompanyAndWritesAudit() throws {
        let tc = try TestCompany.make()
        let targetCompanyId = UUID()

        try RestoreService.prepareRestoredCompanyDatabase(
            db: tc.db,
            restoredCompanyId: targetCompanyId,
            restoredCompanyName: "Restored Co"
        )

        let company = try XCTUnwrap(CompanyRepository(db: tc.db).findById(targetCompanyId))
        XCTAssertEqual(company.name, "Restored Co")
        XCTAssertNil(try CompanyRepository(db: tc.db).findById(tc.companyId))

        let fyCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_financial_years WHERE company_id = ?",
            bind: [.text(targetCompanyId.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(fyCount, 1)

        let accountCount = try tc.db.queryOne(
            "SELECT COUNT(*) FROM mally_accounts WHERE company_id = ?",
            bind: [.text(targetCompanyId.uuidString)]
        ) { $0.int(0) }
        XCTAssertEqual(accountCount, 4)

        let auditEvents = try AuditRepository(db: tc.db).list(filter: .init(companyId: targetCompanyId))
        XCTAssertEqual(auditEvents.count, 1)
        XCTAssertEqual(auditEvents.first?.action, .backupImported)
        XCTAssertEqual(auditEvents.first?.entityId, targetCompanyId.uuidString)
    }

    func testBackupRestoreRoundTripPreservesCompanyData() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let manager = try DatabaseManager(appSupportDirectory: sourceRoot)
        let companyId = UUID()
        _ = try await manager.createCompanyFile(companyId: companyId)
        let dbURL = sourceRoot.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")
        let db = try SQLiteDatabase(path: dbURL.path)
        defer { db.close() }

        let source = try TestCompany.seed(into: db, companyId: companyId, companyName: "Roundtrip Co")
        let entry = CompanyRegistryEntry(id: companyId, name: "Roundtrip Co", sqliteFileName: "\(companyId.uuidString).sqlite")
        try await manager.registerCompany(entry)

        let posted = try VoucherService(db: db, companyId: source.companyId).post(
            draft: source.draft(on: "2024-06-01", lines: [
                source.line(source.cashId, 50000, .debit),
                source.line(source.salesId, 50000, .credit)
            ]),
            in: source.fy
        )

        let backupURL = sourceRoot.appendingPathComponent("roundtrip.mallybackup")
        _ = try await BackupService(manager: manager).export(
            companyId: source.companyId,
            companyName: "Roundtrip Co",
            to: backupURL
        )

        let restoreManager = try DatabaseManager(appSupportDirectory: targetRoot)
        let restored = try await RestoreService(manager: restoreManager).restore(from: backupURL)
        let restoredHandle = try await restoreManager.openCompany(id: restored.id)
        defer { Task { await restoreManager.closeCompany(id: restored.id) } }

        let restoredCompany = try XCTUnwrap(CompanyRepository(db: restoredHandle.db).findById(restored.id))
        XCTAssertEqual(restoredCompany.name, "Roundtrip Co")

        let restoredFY = try XCTUnwrap(FinancialYearRepository(db: restoredHandle.db).findMostRecent(restored.id))
        XCTAssertEqual(restoredFY.label, source.fy.label)

        let restoredVouchers = try VoucherService(db: restoredHandle.db, companyId: restored.id)
            .list(filter: .init(companyId: restored.id))
        XCTAssertEqual(restoredVouchers.count, 1)
        XCTAssertEqual(restoredVouchers.first?.number, posted.voucher.number)
        XCTAssertEqual(restoredVouchers.first?.totalPaise, posted.voucher.totalPaise)

        let restoreAudit = try AuditRepository(db: restoredHandle.db).list(
            filter: .init(companyId: restored.id, action: .backupImported)
        )
        XCTAssertEqual(restoreAudit.count, 1)
    }

    func testRestoreReopenSoakPreservesCompanyDataAcrossRepeatedCycles() async throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let manager = try DatabaseManager(appSupportDirectory: sourceRoot)
        let companyId = UUID()
        _ = try await manager.createCompanyFile(companyId: companyId)
        let dbURL = sourceRoot.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("\(companyId.uuidString).sqlite")
        let db = try SQLiteDatabase(path: dbURL.path)
        defer { db.close() }

        let source = try TestCompany.seed(into: db, companyId: companyId, companyName: "Soak Restore Co")
        let entry = CompanyRegistryEntry(id: companyId, name: "Soak Restore Co", sqliteFileName: "\(companyId.uuidString).sqlite")
        try await manager.registerCompany(entry)

        _ = try VoucherService(db: db, companyId: source.companyId).post(
            draft: source.draft(on: "2024-06-01", lines: [
                source.line(source.cashId, 50000, .debit),
                source.line(source.salesId, 50000, .credit)
            ]),
            in: source.fy
        )

        let backupURL = sourceRoot.appendingPathComponent("soak-restore.mallybackup")
        _ = try await BackupService(manager: manager).export(
            companyId: source.companyId,
            companyName: "Soak Restore Co",
            to: backupURL
        )

        for index in 0..<20 {
            let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: targetRoot) }

            let restoreManager = try DatabaseManager(appSupportDirectory: targetRoot)
            let restored = try await RestoreService(manager: restoreManager).restore(from: backupURL)
            let restoredHandle = try await restoreManager.openCompany(id: restored.id)

            let restoredCompany = try XCTUnwrap(CompanyRepository(db: restoredHandle.db).findById(restored.id))
            XCTAssertEqual(restoredCompany.name, "Soak Restore Co", "Iteration \(index)")

            let restoredFY = try XCTUnwrap(FinancialYearRepository(db: restoredHandle.db).findMostRecent(restored.id))
            XCTAssertEqual(restoredFY.label, source.fy.label, "Iteration \(index)")

            let restoredVouchers = try VoucherService(db: restoredHandle.db, companyId: restored.id)
                .list(filter: .init(companyId: restored.id))
            XCTAssertEqual(restoredVouchers.count, 1, "Iteration \(index)")
            XCTAssertEqual(restoredVouchers.first?.totalPaise, 50000, "Iteration \(index)")

            let balanceSheet = try ReportService(db: restoredHandle.db, companyId: restored.id)
                .balanceSheet(asOfDate: source.fy.endDate, financialYearId: restored.id)
            XCTAssertEqual(balanceSheet.totalAssetsPaise, balanceSheet.totalLiabilitiesPaise + balanceSheet.totalEquityPaise, "Iteration \(index)")

            await restoreManager.closeCompany(id: restored.id)
        }
    }
}
