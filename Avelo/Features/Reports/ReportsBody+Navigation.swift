import SwiftUI

@MainActor
extension ReportsBody {
    func openLedger(_ accountId: Account.ID) {
        ReportsNavigation.openLedger(accountId, vm: vm, router: env.router, dataRevision: env.dataRevision)
    }

    func returnToPreviousReport() {
        ReportsNavigation.returnToPreviousReport(vm: vm, router: env.router)
    }

    func openVoucher(_ id: Voucher.ID) {
        ReportsNavigation.openVoucher(id, router: env.router)
    }
}
