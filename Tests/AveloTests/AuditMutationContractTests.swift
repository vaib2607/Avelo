import XCTest
@testable import Avelo

/// Executable inventory for AVL-P0-034. A shipped mutation may intentionally
/// emit more than one event only when it persists more than one independently
/// meaningful business consequence (for example cancellation plus reversal).
final class AuditMutationContractTests: XCTestCase {
    private enum SnapshotPolicy: String {
        case after
        case beforeAndAfter
        case reasonOnly
    }

    private struct Contract {
        let operation: String
        let actions: [AuditAction]
        let snapshots: SnapshotPolicy
        let reasonRequired: Bool
    }

    private let shipped: [Contract] = [
        .init(operation: "CompanyService.create", actions: [.companyCreated, .financialYearCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "CompanyService.update", actions: [.companyUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "CompanyService.setInventoryMode", actions: [.companyUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "FinancialYearService.create", actions: [.financialYearCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "FinancialYearService.lock", actions: [.financialYearLocked], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "FinancialYearService.unlock", actions: [.financialYearUnlocked], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "FinancialYearService.close", actions: [.openingBalancePosted, .financialYearClosed], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "FinancialYearService.reopen", actions: [.financialYearReopened], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "AccountService.createAccount", actions: [.accountCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "AccountService.updateAccount", actions: [.accountUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "AccountService.disableAccount", actions: [.accountDisabled], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "AccountService.createGroup", actions: [.accountGroupCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "AccountService.updateGroup", actions: [.accountGroupUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "AccountService.deleteGroup", actions: [.accountGroupDeleted], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "VoucherService.post", actions: [.voucherPosted], snapshots: .after, reasonRequired: false),
        .init(operation: "VoucherService.postBatch", actions: [.voucherPosted], snapshots: .after, reasonRequired: false),
        .init(operation: "VoucherService.edit", actions: [.voucherEdited], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "VoucherService.reverse", actions: [.voucherReversed], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "VoucherService.bounceCheque", actions: [.chequeBounced], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "VoucherService.representCheque", actions: [.chequeRepresented], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "VoucherService.cancel", actions: [.voucherReversed, .voucherCancelled], snapshots: .beforeAndAfter, reasonRequired: true),
        .init(operation: "ItemInvoiceService.post", actions: [.voucherPosted, .stockMovementPosted], snapshots: .after, reasonRequired: false),
        .init(operation: "InventoryCostAllocationService.allocate", actions: [.inventoryCostAllocated], snapshots: .after, reasonRequired: false),
        .init(operation: "ItemInvoiceReturnService.post", actions: [.itemInvoiceReturnPosted], snapshots: .after, reasonRequired: true),
        .init(operation: "InventoryService.createItem", actions: [.stockItemCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "InventoryService.updateItem", actions: [.stockItemUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryService.archiveItem", actions: [.stockItemDisabled], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryService.recordMovement", actions: [.stockMovementPosted], snapshots: .after, reasonRequired: false),
        .init(operation: "InventoryService.reverseMovement", actions: [.stockMovementReversed], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryService.replaceMovement", actions: [.stockMovementReversed, .stockMovementPosted], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "BOMService.createBOM", actions: [.billOfMaterialsCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "BOMService.updateBOM", actions: [.billOfMaterialsUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryOrderService.createOrder", actions: [.inventoryOrderCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "InventoryOrderService.recordFulfillment", actions: [.inventoryOrderFulfilled], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryOrderService.closeOrder", actions: [.inventoryOrderStatusChanged], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryOrderService.cancelOrder", actions: [.inventoryOrderStatusChanged], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "InventoryOrderService.setReorderLevel", actions: [.inventoryReorderLevelSet], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "BankReconciliationService.importStatement", actions: [.bankStatementImported], snapshots: .after, reasonRequired: false),
        .init(operation: "BankReconciliationService.clearStatementLine", actions: [.bankStatementLineCleared], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "PayrollService.createEmployee", actions: [.payrollEmployeeCreated], snapshots: .after, reasonRequired: false),
        .init(operation: "PayrollService.updateEmployee", actions: [.payrollEmployeeUpdated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "PayrollService.deactivateEmployee", actions: [.payrollEmployeeTerminated], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "PayrollService.postEntry", actions: [.salaryPosted, .voucherPosted], snapshots: .after, reasonRequired: false),
        .init(operation: "VoucherTemplateService.save", actions: [.voucherTemplateSaved], snapshots: .beforeAndAfter, reasonRequired: false),
        .init(operation: "GSTService.recordExportSaved", actions: [.gstReportExported], snapshots: .reasonOnly, reasonRequired: true),
        .init(operation: "InvoicePDFService.recordExportSaved", actions: [.invoicePDFExported], snapshots: .reasonOnly, reasonRequired: true),
        .init(operation: "BackupService.export", actions: [.backupExported], snapshots: .reasonOnly, reasonRequired: true),
        .init(operation: "RestoreService.restore", actions: [.backupImported], snapshots: .reasonOnly, reasonRequired: true),
        .init(operation: "WindowState.switchCompany", actions: [.companySwitched], snapshots: .reasonOnly, reasonRequired: true),
        .init(operation: "WindowState.switchFinancialYear", actions: [.financialYearSwitched], snapshots: .reasonOnly, reasonRequired: true)
    ]

    func testEveryShippedMutationHasOneUniqueContract() {
        XCTAssertEqual(Set(shipped.map(\.operation)).count, shipped.count)
        XCTAssertTrue(shipped.allSatisfy { !$0.actions.isEmpty })
    }

    func testContractOnlyReferencesPersistedAuditActions() {
        let persisted = Set(AuditAction.allCases)
        XCTAssertTrue(shipped.flatMap(\.actions).allSatisfy(persisted.contains))
    }

    func testEveryPersistedAuditActionIsOwnedByAShippedMutation() {
        let owned = Set(shipped.flatMap(\.actions))
        XCTAssertEqual(owned, Set(AuditAction.allCases))
    }
}
