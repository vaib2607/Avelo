import XCTest
@testable import Avelo

final class Phase6HardeningTests: XCTestCase {

    func testPayrollPostRejectsDuplicateEmployeeMonth() throws {
        let tc = try TestCompany.make()
        let payroll = PayrollService(db: tc.db, companyId: tc.companyId)
        let employee = try payroll.createEmployee(
            name: "Ravi Kumar",
            employeeCode: "EMP-001",
            designation: "Operator",
            pan: nil,
            bankAccount: nil,
            ifsc: nil,
            basicPaise: 50_000,
            hraPaise: 10_000,
            otherAllowancesPaise: 5_000,
            pfApplicable: true,
            esiApplicable: false
        )

        _ = try payroll.postEntry(
            employeeId: employee.id,
            monthYear: 202406,
            workingDays: 30,
            paidDays: 30,
            overtimePaise: 0,
            deductionsPaise: 0,
            financialYearId: tc.fy.id
        )

        XCTAssertThrowsError(
            try payroll.postEntry(
                employeeId: employee.id,
                monthYear: 202406,
                workingDays: 30,
                paidDays: 30,
                overtimePaise: 0,
                deductionsPaise: 0,
                financialYearId: tc.fy.id
            )
        ) { error in
            guard case AppError.duplicateSalary(let message) = error else {
                return XCTFail("Expected duplicateSalary, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("already posted"))
        }
    }

    func testInventorySaleBeyondStockIsRejected() throws {
        let tc = try TestCompany.make()
        let item = try InventoryService(db: tc.db, companyId: tc.companyId).createItem(
            code: "ITEM-1",
            name: "Demo Item",
            unit: "NOS",
            openingQuantity: 2,
            openingRatePaise: 100
        )
        let svc = InventoryService(db: tc.db, companyId: tc.companyId)

        XCTAssertThrowsError(
            try svc.recordMovement(
                itemId: item.id,
                date: DateFormatters.parseDate("2024-06-01")!,
                type: .sale,
                quantity: 5,
                ratePaise: 100
            )
        ) { error in
            guard case AppError.negativeStock(let message) = error else {
                return XCTFail("Expected negativeStock error, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("current stock"))
        }
    }

    func testPercentagePaiseUsesHalfUpRounding() {
        XCTAssertEqual(Currency.percentagePaise(1, ratePercent: 50), 1)
        XCTAssertEqual(Currency.percentagePaise(199, ratePercent: 1), 2)
    }

    func testBackupExportCleansUpExistingDestinationOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DatabaseManager(appSupportDirectory: root)
        let companyId = UUID()
        let sourceURL = root.appendingPathComponent("Companies", isDirectory: true)
            .appendingPathComponent("backup-cleanup.sqlite")
        let db = try SQLiteDatabase(path: sourceURL.path)
        try MigrationRunner().runMigrations(on: db)
        _ = try TestCompany.seed(into: db, companyId: companyId, companyName: "Backup Cleanup Co")
        db.close()

        try await manager.registerCompany(
            CompanyRegistryEntry(id: companyId, name: "Backup Cleanup Co", sqliteFileName: sourceURL.lastPathComponent)
        )

        let destinationURL = root
            .appendingPathComponent("missing-output-dir", isDirectory: true)
            .appendingPathComponent("existing-backup.avelobackup")

        do {
            _ = try await BackupService(manager: manager).export(
                companyId: companyId,
                companyName: "Backup Cleanup Co",
                to: destinationURL
            )
            XCTFail("Expected backup export to fail")
        } catch {
            let leftover = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
                .filter { $0.contains("avelo-backup-") && $0.contains("existing-backup.avelobackup") }
            XCTAssertTrue(leftover.isEmpty)
        }
    }

    func testDeleteAccountGroupBlocksWhenChildrenExist() throws {
        let tc = try TestCompany.make()
        let accountService = AccountService(db: tc.db, companyId: tc.companyId)
        let parent = try accountService.createGroup(code: "6000", name: "Parent", nature: .assets)
        let child = try accountService.createGroup(code: "6100", name: "Child", nature: .assets, parentGroupId: parent.id)
        _ = try accountService.createAccount(.init(
            code: "6101",
            name: "Ledger Child",
            groupId: child.id,
            openingBalancePaise: 0,
            openingBalanceSide: .debit,
            gstin: nil,
            existingAccountId: nil
        ))

        XCTAssertThrowsError(try accountService.deleteGroup(parent.id)) { error in
            guard case AppError.groupHasChildren(let message) = error else {
                return XCTFail("Expected groupHasChildren, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("child groups"))
        }
    }
}
