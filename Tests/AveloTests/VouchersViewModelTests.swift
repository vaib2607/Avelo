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
