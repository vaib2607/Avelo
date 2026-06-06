import Foundation

public final class VoucherService: Sendable {

    public let db: SQLiteDatabase
    public let repository: VoucherRepository
    public let linesRepository: LedgerLineRepository
    public let sequenceRepository: VoucherSequenceRepository
    public let fiscalLockChecker: FiscalLockChecker
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = VoucherRepository(db: db)
        self.linesRepository = LedgerLineRepository(db: db)
        self.sequenceRepository = VoucherSequenceRepository(db: db)
        self.fiscalLockChecker = FiscalLockChecker(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public struct PostResult: Sendable {
        public let voucher: Voucher
        public let inventoryPrompt: InventoryPromptContext?
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear) throws -> PostResult {
        let result = try validate(draft: draft, in: fy)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }

        let number = try sequenceRepository.nextNumber(
            companyId: companyId,
            financialYearId: fy.id,
            typeCode: draft.voucherTypeCode
        )
        let voucherId = UUID()
        let now = Date()
        let total = draft.totalDebitPaise

        let lines: [LedgerLine] = draft.filledLines.enumerated().map { (idx, line) in
            LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: line.accountId!,
                amountPaise: line.amountPaise,
                side: line.side,
                taxCode: line.taxCode,
                costCenter: line.costCenter,
                lineOrder: idx
            )
        }
        let voucher = Voucher(
            id: voucherId,
            companyId: companyId,
            financialYearId: fy.id,
            voucherTypeCode: draft.voucherTypeCode,
            number: number,
            date: draft.date,
            partyAccountId: draft.partyAccountId,
            narration: draft.narration,
            isReversal: false,
            reversalOfId: nil,
            isPosted: true,
            totalPaise: total,
            createdAt: now,
            updatedAt: now
        )

        try db.write { tx in
            let vRepo = VoucherRepository(db: tx)
            let lRepo = LedgerLineRepository(db: tx)
            try vRepo.insert(voucher)
            try lRepo.insertBatch(lines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherPosted,
                entityType: "voucher",
                entityId: voucher.id.uuidString,
                snapshotAfter: voucher
            )
            for line in lines {
                if let accId = try? line.accountId.uuidString {
                    try? AccountRepository(db: tx).markUsed(UUID(uuidString: accId) ?? UUID())
                }
            }
        }

        let prompt: InventoryPromptContext? = nil
        return PostResult(voucher: voucher, inventoryPrompt: prompt)
    }

    public func edit(_ voucherId: Voucher.ID, with newDraft: VoucherDraft, in fy: FinancialYear) throws -> Voucher {
        guard let existing = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        let result = try validate(draft: newDraft, in: fy, existingVoucherId: voucherId)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        let existingLines = try linesRepository.findForVoucher(voucherId)
        var updated = existing
        updated.date = newDraft.date
        updated.partyAccountId = newDraft.partyAccountId
        updated.narration = newDraft.narration
        updated.totalPaise = newDraft.totalDebitPaise
        updated.updatedAt = Date()
        let newLines: [LedgerLine] = newDraft.filledLines.enumerated().map { (idx, line) in
            LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: line.accountId!,
                amountPaise: line.amountPaise,
                side: line.side,
                taxCode: line.taxCode,
                costCenter: line.costCenter,
                lineOrder: idx
            )
        }
        try db.write { tx in
            let vRepo = VoucherRepository(db: tx)
            let lRepo = LedgerLineRepository(db: tx)
            try vRepo.update(updated)
            try lRepo.deleteForVoucher(voucherId)
            try lRepo.insertBatch(newLines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherEdited,
                entityType: "voucher",
                entityId: voucherId.uuidString,
                snapshotBefore: existing,
                snapshotAfter: updated
            )
        }
        return updated
    }

    public func reverse(_ voucherId: Voucher.ID, reason: String? = nil) throws -> Voucher {
        guard let original = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard let originalFY = try FinancialYearRepository(db: db).findById(original.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        if try fiscalLockChecker.isLocked(financialYearId: originalFY.id) {
            throw AppError.businessRule("Cannot reverse: source financial year is locked.")
        }
        let originalLines = try linesRepository.findForVoucher(voucherId)
        let number = try sequenceRepository.nextNumber(
            companyId: companyId,
            financialYearId: originalFY.id,
            typeCode: original.voucherTypeCode
        )
        let reversalId = UUID()
        let now = Date()
        let flippedLines: [LedgerLine] = originalLines.enumerated().map { (idx, line) in
            LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: reversalId,
                accountId: line.accountId,
                amountPaise: line.amountPaise,
                side: line.side == .debit ? .credit : .debit,
                taxCode: line.taxCode,
                costCenter: line.costCenter,
                lineOrder: idx
            )
        }
        let reversal = Voucher(
            id: reversalId,
            companyId: companyId,
            financialYearId: originalFY.id,
            voucherTypeCode: original.voucherTypeCode,
            number: number,
            date: now,
            partyAccountId: original.partyAccountId,
            narration: "Reversal of \(original.number)" + (reason.map { ": \($0)" } ?? ""),
            isReversal: true,
            reversalOfId: voucherId,
            isPosted: true,
            totalPaise: original.totalPaise,
            createdAt: now,
            updatedAt: now
        )
        try db.write { tx in
            let vRepo = VoucherRepository(db: tx)
            let lRepo = LedgerLineRepository(db: tx)
            try vRepo.insert(reversal)
            try lRepo.insertBatch(flippedLines)
            try vRepo.markReversal(originalId: voucherId, reversalId: reversalId)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherReversed,
                entityType: "voucher",
                entityId: reversalId.uuidString,
                snapshotBefore: original,
                snapshotAfter: reversal,
                reason: reason
            )
        }
        return reversal
    }

    public func validate(draft: VoucherDraft,
                         in fy: FinancialYear,
                         existingVoucherId: Voucher.ID? = nil) throws -> ValidationResult {
        let validator = VoucherDraftValidator(db: db, fiscalLockChecker: fiscalLockChecker)
        return validator.validate(draft, companyId: companyId,
                                  financialYearId: fy.id,
                                  existingVoucherId: existingVoucherId)
    }

    public func list(filter: VoucherRepository.Filter) throws -> [Voucher] {
        try repository.list(filter: filter)
    }

    public func findById(_ id: Voucher.ID) throws -> Voucher? {
        try repository.findById(id)
    }

    public func lines(for voucherId: Voucher.ID) throws -> [LedgerLine] {
        try linesRepository.findForVoucher(voucherId)
    }

    public func loadDraft(from voucherId: Voucher.ID) throws -> VoucherDraft {
        guard let voucher = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        let lines = try linesRepository.findForVoucher(voucherId)
        return VoucherDraft(
            mode: .edit(originalVoucherId: voucherId),
            voucherTypeCode: voucher.voucherTypeCode,
            date: voucher.date,
            partyAccountId: voucher.partyAccountId,
            narration: voucher.narration,
            reference: "",
            lines: lines.enumerated().map { (idx, line) in
                VoucherDraft.Line(
                    accountId: line.accountId,
                    amountPaise: line.amountPaise,
                    side: line.side,
                    taxCode: line.taxCode,
                    costCenter: line.costCenter,
                    lineOrder: idx
                )
            }
        )
    }
}
