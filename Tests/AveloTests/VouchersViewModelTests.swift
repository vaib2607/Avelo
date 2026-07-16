import XCTest
@testable import Avelo

@MainActor
final class VouchersViewModelTests: XCTestCase {

    func testReloadIgnoresStaleDetachedResultAfterNewerReloadStarts() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        _ = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Alpha", lines: [
            tc.line(tc.cashId, 25000, .debit),
            tc.line(tc.salesId, 25000, .credit)
        ]), in: tc.fy)
        _ = try svc.post(draft: tc.draft(on: "2024-06-02", narration: "Beta", lines: [
            tc.line(tc.rentId, 15000, .debit),
            tc.line(tc.cashId, 15000, .credit)
        ]), in: tc.fy)

        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        let firstResultsReady = expectation(description: "first results ready")
        let gate = ReloadGate()
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

        let done = expectation(description: "reload finished")
        Task {
            while vm.isLoading {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(vm.vouchers.map(\.narration), ["Beta"])
    }

    func testReloadRespectsPaginationLimitAndOffset() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        for idx in 0..<12 {
            _ = try svc.post(draft: tc.draft(
                on: "2024-06-\(String(format: "%02d", idx + 1))",
                narration: "Voucher \(idx)",
                lines: [
                    tc.line(tc.cashId, 1000 + Int64(idx), .debit),
                    tc.line(tc.salesId, 1000 + Int64(idx), .credit)
                ]
            ), in: tc.fy)
        }

        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.limit = 5
        vm.offset = 4
        vm.reload()

        let done = expectation(description: "page loaded")
        Task {
            while vm.isLoading {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(vm.vouchers.count, 5)
        XCTAssertEqual(vm.vouchers.map(\.narration), ["Voucher 7", "Voucher 6", "Voucher 5", "Voucher 4", "Voucher 3"])
        XCTAssertEqual(vm.pagination.totalCount, 12)
    }

    // AVL-P2-013 (PgUp/PgDn): selection moves within the loaded page only,
    // without touching filter/pagination state (no reload() call at all).

    private func waitForLoad(_ vm: VouchersViewModel) {
        let done = expectation(description: "page loaded")
        Task {
            while vm.isLoading {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testSelectNextAndPreviousMoveThroughLoadedPageWithoutTouchingFilterState() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        for idx in 0..<3 {
            _ = try svc.post(draft: tc.draft(
                on: "2024-06-0\(idx + 1)", narration: "Voucher \(idx)",
                lines: [tc.line(tc.cashId, 1000, .debit), tc.line(tc.salesId, 1000, .credit)]
            ), in: tc.fy)
        }
        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.query = "Voucher"
        vm.reload()
        waitForLoad(vm)
        XCTAssertEqual(vm.vouchers.count, 3)

        XCTAssertNil(vm.selectedVoucherId)
        vm.selectNext()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[0].id)
        vm.selectNext()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[1].id)
        vm.selectPrevious()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[0].id)

        // Boundary: previous at the first row is a no-op, not wraparound.
        vm.selectPrevious()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[0].id)

        // Filter/pagination state untouched by any of the above.
        XCTAssertEqual(vm.query, "Voucher")
        XCTAssertEqual(vm.pagination.offset, 0)
    }

    func testSelectNextAtLastRowIsANoOp() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)
        _ = try svc.post(draft: tc.draft(on: "2024-06-01", narration: "Only voucher", lines: [
            tc.line(tc.cashId, 1000, .debit), tc.line(tc.salesId, 1000, .credit)
        ]), in: tc.fy)
        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.reload()
        waitForLoad(vm)

        vm.selectNext()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[0].id)
        vm.selectNext()
        XCTAssertEqual(vm.selectedVoucherId, vm.vouchers[0].id)
    }

    func testPagedReloadReplacesRowsWithoutDuplicatesWhenOlderPageFinishesLate() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        for idx in 0..<12 {
            _ = try svc.post(draft: tc.draft(
                on: "2024-06-\(String(format: "%02d", idx + 1))",
                narration: "Paged \(idx)",
                lines: [
                    tc.line(tc.cashId, 1000 + Int64(idx), .debit),
                    tc.line(tc.salesId, 1000 + Int64(idx), .credit)
                ]
            ), in: tc.fy)
        }

        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.limit = 5
        let firstResultsReady = expectation(description: "first page results ready")
        let gate = ReloadGate()
        vm.onResultsReady = {
            firstResultsReady.fulfill()
            while !gate.isOpen {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        vm.reload()
        wait(for: [firstResultsReady], timeout: 5)

        vm.onResultsReady = nil
        vm.pagination.totalCount = 12
        vm.nextPage()
        gate.open()

        let done = expectation(description: "next page loaded")
        Task {
            while vm.isLoading {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(vm.offset, 5)
        XCTAssertEqual(vm.vouchers.count, 5)
        XCTAssertEqual(Set(vm.vouchers.map(\.id)).count, 5)
        XCTAssertEqual(vm.vouchers.map(\.narration), ["Paged 6", "Paged 5", "Paged 4", "Paged 3", "Paged 2"])
    }

    func testFilterReloadResetsToFirstPage() throws {
        let tc = try TestCompany.make()
        let svc = VoucherService(db: tc.db, companyId: tc.companyId)

        for idx in 0..<8 {
            _ = try svc.post(draft: tc.draft(
                on: "2024-06-\(String(format: "%02d", idx + 1))",
                narration: idx < 4 ? "Alpha \(idx)" : "Beta \(idx)",
                lines: [
                    tc.line(tc.cashId, 1000 + Int64(idx), .debit),
                    tc.line(tc.salesId, 1000 + Int64(idx), .credit)
                ]
            ), in: tc.fy)
        }

        let vm = VouchersViewModel(companyId: tc.companyId, db: tc.db, fyId: tc.fy.id)
        vm.limit = 3
        vm.pagination.totalCount = 8
        vm.nextPage()
        XCTAssertEqual(vm.offset, 3)

        vm.query = "Alpha"
        vm.reloadFirstPage()

        let done = expectation(description: "filtered first page loaded")
        Task {
            while vm.isLoading {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(vm.offset, 0)
        XCTAssertEqual(vm.pagination.totalCount, 4)
        XCTAssertEqual(vm.vouchers.map(\.narration), ["Alpha 3", "Alpha 2", "Alpha 1"])
    }
}

private final class ReloadGate {
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
