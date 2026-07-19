import Foundation

/// The only feature-level owner of create/edit voucher submission. UI routes
/// may commit focused controls first, but never call posting services directly.
@MainActor
enum VoucherEditorOperation {
    case create(voucherType: VoucherType.Code, financialYear: FinancialYear)
    case edit(voucherId: Voucher.ID, financialYear: FinancialYear)
}

/// A shared focus vocabulary for both voucher editors.
enum VoucherEditorFocusTarget: Hashable {
    case date
    case party
    case narration
    case billReferenceNumber
    case chequeNumber
    case chequeDueDate
    case accountLedger
    case salesPurchaseLedger
    case ledgerAccount(UUID)
    case ledgerAmount(UUID)
    case item(UUID)
    case quantity(UUID)
    case rate(UUID)
    case post
}

enum VoucherEditorSubmissionOutcome {
    case posted
    case validationFailed(ValidationError?)
    case failed(AppError)
}

@MainActor
enum VoucherEditorSubmission {
    static func submit(vm: VoucherEditViewModel,
                       operation: VoucherEditorOperation,
                       db: SQLiteDatabase,
                       companyId: Company.ID) -> VoucherEditorSubmissionOutcome {
        guard vm.beginSubmission() else {
            return .failed(.businessRule("Voucher submission is already in progress."))
        }
        defer { vm.endSubmission() }
        do {
            switch operation {
            case let .create(voucherType, financialYear):
                try vm.prepareForSubmission()
                if vm.itemInvoiceMode {
                    guard let party = vm.partyAccountId,
                          let ledger = vm.salesOrPurchaseLedgerId else {
                        throw AppError.businessRule(vm.itemInvoiceValidationErrors.first ?? "This voucher isn't ready to post yet.")
                    }
                    guard vm.itemInvoiceValidationErrors.isEmpty else {
                        throw AppError.businessRule(vm.itemInvoiceValidationErrors[0])
                    }
                    _ = try ItemInvoiceService(db: db, companyId: companyId).post(
                        voucherTypeCode: voucherType,
                        date: vm.date,
                        partyAccountId: party,
                        salesOrPurchaseLedgerId: ledger,
                        items: vm.buildItemLineInputs(),
                        narration: vm.narration,
                        billReferenceType: vm.billReferenceType,
                        billReferenceNumber: vm.billReferenceNumber.isEmpty ? nil : vm.billReferenceNumber,
                        in: financialYear
                    )
                } else {
                    _ = try VoucherService(db: db, companyId: companyId).post(
                        draft: vm.buildDraft(), in: financialYear, workflow: vm.buildWorkflowInputs()
                    )
                }
            case let .edit(voucherId, financialYear):
                try vm.prepareForSubmission()
                _ = try VoucherService(db: db, companyId: companyId).edit(
                    voucherId, with: vm.buildDraft(), in: financialYear, workflow: vm.buildWorkflowInputs()
                )
            }
            return .posted
        } catch {
            let appError = AppError.wrap(error)
            vm.setLocalEditorError(appError)
            if case .validation(let validationError) = appError {
                return .validationFailed(validationError)
            }
            return .failed(appError)
        }
    }
}
