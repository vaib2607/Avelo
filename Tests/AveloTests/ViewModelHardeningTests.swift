import XCTest
@testable import Avelo

@MainActor
final class ViewModelHardeningTests: XCTestCase {

    func testAuditReloadIgnoresStaleSearchResults() throws {
        let tc = try TestCompany.make()
        let audit = AuditService(db: tc.db, companyId: tc.companyId)
        try audit.record(action: .accountCreated, entityType: "account", entityId: "alpha", reason: "Alpha search row")
        try audit.record(action: .accountUpdated, entityType: "account", entityId: "beta", reason: "Beta search row")

        let vm = AuditViewModel(companyId: tc.companyId, db: tc.db)
        let firstResultsReady = expectation(description: "first audit results ready")
        let gate = HardeningReloadGate()
        vm.onResultsReady = {
            firstResultsReady.fulfill()
            while !gate.isOpen {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        vm.query = "Alpha"
        vm.reload()
        wait(for: [firstResultsReady], timeout: 5)

        vm.onResultsReady = nil
        vm.query = "Beta"
        vm.reload()
        gate.open()

        waitForReload(vm)
        XCTAssertEqual(vm.events.map(\.entityId), ["beta"])
    }

    func testAccountsReloadIgnoresStaleResultsAndRespectsPagination() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        for idx in 0..<8 {
            _ = try service.createAccount(.init(
                code: "A\(String(format: "%03d", idx))",
                name: "Account \(idx)",
                groupId: tc.assetsGroupId,
                openingBalancePaise: 0,
                openingBalanceSide: .debit,
                gstin: nil,
                existingAccountId: nil
            ))
        }

        let vm = AccountsViewModel(companyId: tc.companyId, db: tc.db)
        let firstResultsReady = expectation(description: "first account results ready")
        let gate = HardeningReloadGate()
        vm.limit = 2
        vm.offset = 0
        vm.onResultsReady = {
            firstResultsReady.fulfill()
            while !gate.isOpen {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        vm.reload()
        wait(for: [firstResultsReady], timeout: 5)

        vm.onResultsReady = nil
        vm.offset = 4
        vm.reload()
        gate.open()

        waitForReload(vm)
        XCTAssertEqual(vm.accounts.map(\.code), ["A001", "A002"])
        XCTAssertEqual(vm.pagination.totalCount, 18)
    }

    func testInventoryReloadIgnoresStaleResultsAndRespectsPagination() throws {
        let tc = try TestCompany.make()
        let service = InventoryService(db: tc.db, companyId: tc.companyId)
        for idx in 0..<8 {
            _ = try service.createItem(
                code: "SKU\(String(format: "%03d", idx))",
                name: "Item \(idx)",
                unit: "NOS"
            )
        }

        let vm = InventoryViewModel(companyId: tc.companyId, db: tc.db)
        let firstResultsReady = expectation(description: "first inventory results ready")
        let gate = HardeningReloadGate()
        vm.limit = 2
        vm.offset = 0
        vm.onResultsReady = {
            firstResultsReady.fulfill()
            while !gate.isOpen {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        vm.reload()
        wait(for: [firstResultsReady], timeout: 5)

        vm.onResultsReady = nil
        vm.offset = 4
        vm.reload()
        gate.open()

        waitForReload(vm)
        XCTAssertEqual(vm.items.map(\.code), ["SKU004", "SKU005"])
        XCTAssertEqual(vm.pagination.totalCount, 8)
    }

    func testPayrollReloadIgnoresStaleResults() throws {
        let tc = try TestCompany.make()
        let service = PayrollService(db: tc.db, companyId: tc.companyId)
        let employee = try service.createEmployee(
            name: "Alpha Employee",
            employeeCode: "EMP001",
            designation: nil,
            pan: nil,
            baseSalaryPaise: 50_000_00
        )
        _ = try service.createEmployee(
            name: "Beta Employee",
            employeeCode: "EMP002",
            designation: nil,
            pan: nil,
            baseSalaryPaise: 60_000_00
        )
        _ = try service.postEntry(
            employeeId: employee.id,
            monthYear: 202404,
            deductionsPaise: 0,
            financialYearId: tc.fy.id,
            salaryExpenseAccountId: tc.rentId,
            paymentAccountId: tc.cashId
        )

        let vm = PayrollViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        let firstResultsReady = expectation(description: "first payroll results ready")
        let gate = HardeningReloadGate()
        vm.onResultsReady = {
            firstResultsReady.fulfill()
            while !gate.isOpen {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        vm.monthYear = 202404
        vm.reload()
        wait(for: [firstResultsReady], timeout: 5)

        vm.onResultsReady = nil
        vm.monthYear = 202405
        vm.reload()
        gate.open()

        waitForReload(vm)
        XCTAssertEqual(vm.employees.map(\.employeeCode), ["EMP001", "EMP002"])
        XCTAssertTrue(vm.entries.isEmpty)
    }

    private func waitForReload(_ vm: AuditViewModel, file: StaticString = #filePath, line: UInt = #line) {
        waitUntilNotLoading({ vm.isLoading }, file: file, line: line)
    }

    private func waitForReload(_ vm: AccountsViewModel, file: StaticString = #filePath, line: UInt = #line) {
        waitUntilNotLoading({ vm.isLoading }, file: file, line: line)
    }

    private func waitForReload(_ vm: InventoryViewModel, file: StaticString = #filePath, line: UInt = #line) {
        waitUntilNotLoading({ vm.isLoading }, file: file, line: line)
    }

    private func waitForReload(_ vm: PayrollViewModel, file: StaticString = #filePath, line: UInt = #line) {
        waitUntilNotLoading({ vm.isLoading }, file: file, line: line)
    }

    private func waitUntilNotLoading(_ isLoading: @escaping @MainActor () -> Bool,
                                     file: StaticString,
                                     line: UInt) {
        let done = expectation(description: "reload finished")
        Task {
            while isLoading() {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}

private final class HardeningReloadGate {
    private let lock = NSLock()
    private var openState = false

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return openState
    }

    func open() {
        lock.lock()
        openState = true
        lock.unlock()
    }
}
