import SwiftUI

@MainActor
extension ReportsBody {
    func openLedger(_ accountId: Account.ID) {
        vm.selection = .ledger
        vm.ledgerAccountId = accountId
        vm.reload()
    }

    func openVoucher(_ id: Voucher.ID) {
        ReportsNavigation.openVoucher(id, router: env.router)
    }
}
