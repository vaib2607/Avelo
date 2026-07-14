import XCTest
@testable import Avelo

@MainActor
final class NewVoucherAccountCreationTests: XCTestCase {
    func testCreateAccountViaAltCFlowSelectsNewAccountAndLeavesDraftStateUnchanged() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        let vm = VoucherEditViewModel(companyId: tc.companyId, db: tc.db,
                                      fyId: tc.fy.id, initialType: .journal)
        vm.load(accounts: try service.listActiveAccounts(), groups: try service.listGroups(), initialDate: tc.fy.startDate)
        vm.narration = "Keep this narration"
        vm.partyAccountId = tc.salesId
        let originalDate = vm.date
        let originalLines = vm.lines
        let beforeIDs = Set(vm.accounts.map(\.id))

        let created = try service.createAccount(.init(
            code: "ALT_C", name: "Alt C Account", groupId: tc.assetsGroupId,
            openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil,
            existingAccountId: nil))
        vm.accounts = try service.listActiveAccounts()
        let selection = accountCreationSelection(
            before: beforeIDs,
            accounts: vm.accounts,
            eligibility: { _ in true }
        )
        guard case .selected(let createdID) = selection else {
            return XCTFail("Expected the eligible new account to be selected")
        }
        vm.partyAccountId = createdID

        XCTAssertEqual(vm.partyAccountId, created.id)
        XCTAssertEqual(vm.narration, "Keep this narration")
        XCTAssertEqual(vm.date, originalDate)
        XCTAssertEqual(vm.lines, originalLines)
    }

    func testCreateAccountRejectsNewAccountOutsidePickerEligibility() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        let beforeIDs = Set(try service.listActiveAccounts().map(\.id))

        let created = try service.createAccount(.init(
            code: "NOT_CASH", name: "Not Cash Or Bank", groupId: tc.assetsGroupId,
            openingBalancePaise: 0, openingBalanceSide: .debit, gstin: nil,
            existingAccountId: nil
        ))
        let selection = accountCreationSelection(
            before: beforeIDs,
            accounts: try service.listActiveAccounts(),
            eligibility: { $0.isBankAccount || $0.code == "CASH_IN_HAND" }
        )

        XCTAssertEqual(selection, .rejected(created.id))
    }
}
