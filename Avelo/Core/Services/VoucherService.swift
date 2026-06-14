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

    struct VoucherAuditSnapshot: Sendable, Codable {
        let voucher: Voucher
        let lines: [LedgerLine]
    }

    public struct WorkflowInputs: Sendable {
        public var billAllocationKind: BillAllocationKind?
        public var billAllocationNumber: String?
        public var chequeNumber: String?
        public var chequeDueDate: Date?
        public var chequeStatus: ChequeStatus?
        public var postDatedDate: Date?
        public var tdsSectionCode: String?
        public var tdsTaxPaise: Int64?
        public var tcsSectionCode: String?
        public var tcsTaxPaise: Int64?
        public init(billAllocationKind: BillAllocationKind? = nil,
                    billAllocationNumber: String? = nil,
                    chequeNumber: String? = nil,
                    chequeDueDate: Date? = nil,
                    chequeStatus: ChequeStatus? = nil,
                    postDatedDate: Date? = nil,
                    tdsSectionCode: String? = nil,
                    tdsTaxPaise: Int64? = nil,
                    tcsSectionCode: String? = nil,
                    tcsTaxPaise: Int64? = nil) {
            self.billAllocationKind = billAllocationKind
            self.billAllocationNumber = billAllocationNumber
            self.chequeNumber = chequeNumber
            self.chequeDueDate = chequeDueDate
            self.chequeStatus = chequeStatus
            self.postDatedDate = postDatedDate
            self.tdsSectionCode = tdsSectionCode
            self.tdsTaxPaise = tdsTaxPaise
            self.tcsSectionCode = tcsSectionCode
            self.tcsTaxPaise = tcsTaxPaise
        }
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear) throws -> PostResult {
        defer { ReportService.invalidateCache(companyId: companyId) }
        return try postWithoutCacheInvalidation(draft: draft, in: fy)
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear, workflow: WorkflowInputs) throws -> PostResult {
        var result: PostResult?
        try db.write { tx in
            let posted = try postWithoutCacheInvalidation(draft: draft, in: fy)
            try recordWorkflow(posted.voucher, draft: draft, workflow: workflow, in: tx)
            result = posted
        }
        ReportService.invalidateCache(companyId: companyId)
        guard let result else {
            throw AppError.unexpected("workflow post did not produce a result")
        }
        return result
    }

    public func postBatch(_ drafts: [VoucherDraft], in fy: FinancialYear) throws -> [PostResult] {
        var results: [PostResult] = []
        results.reserveCapacity(drafts.count)
        let chunkSize = 500
        var index = drafts.startIndex
        while index < drafts.endIndex {
            let end = drafts.index(index, offsetBy: chunkSize, limitedBy: drafts.endIndex) ?? drafts.endIndex
            try db.write { _ in
                for draft in drafts[index..<end] {
                    try autoreleasepool {
                        results.append(try postWithoutCacheInvalidation(draft: draft, in: fy))
                    }
                }
            }
            index = end
        }
        ReportService.invalidateCache(companyId: companyId)
        return results
    }

    private func postWithoutCacheInvalidation(draft: VoucherDraft, in fy: FinancialYear) throws -> PostResult {
        let result = try validate(draft: draft, in: fy)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }

        let voucherId = UUID()
        let now = Date()
        let total = draft.totalDebitPaise

        let lines: [LedgerLine] = try draft.filledLines.enumerated().map { (idx, line) in
            guard let accountId = line.accountId else {
                throw AppError.validation(.init(code: .internal, message: "Voucher line account is required"))
            }
            return LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: accountId,
                amountPaise: line.amountPaise,
                side: line.side,
                taxCode: line.taxCode,
                costCenter: line.costCenter,
                lineOrder: idx
            )
        }
        var voucher: Voucher!
        try db.write { tx in
            let number = try VoucherSequenceRepository(db: tx).nextNumber(
                companyId: companyId,
                financialYearId: fy.id,
                typeCode: draft.voucherTypeCode
            )
            voucher = Voucher(
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
            let vRepo = VoucherRepository(db: tx)
            let lRepo = LedgerLineRepository(db: tx)
            let accountRepo = AccountRepository(db: tx)
            try vRepo.insert(voucher)
            try lRepo.insertBatch(lines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherPosted,
                entityType: "voucher",
                entityId: voucher.id.uuidString,
                snapshotAfter: VoucherAuditSnapshot(voucher: voucher, lines: lines)
            )
            try markAccountsUsed(accountRepo, lines: lines)
        }

        let prompt = try inventoryPromptContext(for: voucher)
        return PostResult(voucher: voucher, inventoryPrompt: prompt)
    }

    private func inventoryPromptContext(for voucher: Voucher) throws -> InventoryPromptContext? {
        guard voucher.voucherTypeCode == .sales || voucher.voucherTypeCode == .purchase else {
            return nil
        }
        guard let company = try CompanyRepository(db: db).findById(companyId),
              company.isInventoryEnabled,
              company.inventoryLinkMode == .autoPrompt else {
            return nil
        }
        return InventoryPromptContext(voucherId: voucher.id, voucherNumber: voucher.number, lines: [])
    }

    private func recordWorkflow(_ voucher: Voucher, draft: VoucherDraft, workflow: WorkflowInputs, in db: SQLiteDatabase) throws {
        let repo = AccountingWorkflowsRepository(db: db)
        if let kind = workflow.billAllocationKind, let party = voucher.partyAccountId {
            try repo.insert(BillAllocation(companyId: companyId, voucherId: voucher.id, partyAccountId: party, kind: kind, referenceNumber: workflow.billAllocationNumber, allocatedPaise: voucher.totalPaise))
        }
        if let chequeNumber = workflow.chequeNumber {
            try repo.insert(Cheque(companyId: companyId, voucherId: voucher.id, chequeNumber: chequeNumber, issueDate: voucher.date, dueDate: workflow.chequeDueDate, status: workflow.chequeStatus ?? (workflow.chequeDueDate != nil ? .issued : .deposited)))
        }
        if let tdsSectionCode = workflow.tdsSectionCode, let tdsTaxPaise = workflow.tdsTaxPaise {
            try repo.insert(TDSRecord(companyId: companyId, voucherId: voucher.id, sectionCode: tdsSectionCode, basePaise: voucher.totalPaise, taxPaise: tdsTaxPaise))
        }
        if let tcsSectionCode = workflow.tcsSectionCode, let tcsTaxPaise = workflow.tcsTaxPaise {
            try repo.insert(TCSRecord(companyId: companyId, voucherId: voucher.id, sectionCode: tcsSectionCode, basePaise: voucher.totalPaise, taxPaise: tcsTaxPaise))
        }
        if let postDatedDate = workflow.postDatedDate {
            var updated = voucher
            updated.date = postDatedDate
            try VoucherRepository(db: db).update(updated)
        }
    }

    public func edit(_ voucherId: Voucher.ID, with newDraft: VoucherDraft, in fy: FinancialYear) throws -> Voucher {
        guard let existing = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard let existingFY = try FinancialYearRepository(db: db).findById(existing.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        if existing.isReversal {
            throw AppError.businessRule("Reversal vouchers cannot be edited.")
        }
        if try repository.hasReversal(for: voucherId) {
            throw AppError.businessRule("This voucher has already been reversed and cannot be edited in place.")
        }
        let existingLines = try linesRepository.findForVoucher(voucherId)
        let existingWorkflow = try AccountingWorkflowsRepository(db: db).workflowInputs(for: voucherId)
        let result = try validate(draft: newDraft, in: existingFY, existingVoucherId: voucherId)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        var updated = existing
        updated.date = newDraft.date
        updated.partyAccountId = newDraft.partyAccountId
        updated.narration = newDraft.narration
        updated.totalPaise = newDraft.totalDebitPaise
        updated.updatedAt = Date()
        let newLines: [LedgerLine] = try newDraft.filledLines.enumerated().map { (idx, line) in
            guard let accountId = line.accountId else {
                throw AppError.validation(.init(code: .internal, message: "Voucher line account is required"))
            }
            return LedgerLine(
                id: UUID(),
                companyId: companyId,
                voucherId: voucherId,
                accountId: accountId,
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
            let accountRepo = AccountRepository(db: tx)
            let workflowRepo = AccountingWorkflowsRepository(db: tx)
            try vRepo.update(updated)
            try lRepo.deleteForVoucher(voucherId)
            try lRepo.insertBatch(newLines)
            try workflowRepo.deleteForVoucher(voucherId)
            try recordWorkflow(updated, draft: newDraft, workflow: existingWorkflow, in: tx)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherEdited,
                entityType: "voucher",
                entityId: voucherId.uuidString,
                snapshotBefore: VoucherAuditSnapshot(voucher: existing, lines: existingLines),
                snapshotAfter: VoucherAuditSnapshot(voucher: updated, lines: newLines)
            )
            try markAccountsUsed(accountRepo, lines: newLines)
        }
        ReportService.invalidateCache(companyId: companyId)
        return updated
    }

    public func reverse(_ voucherId: Voucher.ID, reason: String? = nil) throws -> Voucher {
        guard let original = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard let originalFY = try FinancialYearRepository(db: db).findById(original.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        if original.isReversal {
            throw AppError.businessRule("A reversal voucher cannot be reversed again.")
        }
        if try repository.hasReversal(for: voucherId) {
            throw AppError.businessRule("This voucher has already been reversed.")
        }
        let targetFY = try reversalFinancialYear(for: originalFY)
        let originalLines = try linesRepository.findForVoucher(voucherId)
        let number = try sequenceRepository.nextNumber(
            companyId: companyId,
            financialYearId: targetFY.id,
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
                side: line.side == EntrySide.debit ? EntrySide.credit : EntrySide.debit,
                taxCode: line.taxCode,
                costCenter: line.costCenter,
                lineOrder: idx
            )
        }
        let reversalDate: Date = {
            if now < targetFY.startDate { return targetFY.startDate }
            if now > targetFY.endDate { return targetFY.endDate }
            return now
        }()
        let reversalDraft = VoucherDraft(
            mode: .create,
            voucherTypeCode: original.voucherTypeCode,
            date: reversalDate,
            partyAccountId: original.partyAccountId,
            narration: "Reversal of \(original.number)" + (reason.map { ": \($0)" } ?? ""),
            lines: flippedLines.map { line in
                VoucherDraft.Line(
                    accountId: line.accountId,
                    amountPaise: line.amountPaise,
                    side: line.side,
                    taxCode: line.taxCode,
                    costCenter: line.costCenter,
                    lineOrder: line.lineOrder
                )
            }
        )
        let validation = try validate(draft: reversalDraft, in: targetFY)
        if case .invalid(let errs) = validation, let first = errs.first {
            throw AppError.validation(first)
        }
        let reversal = Voucher(
            id: reversalId,
            companyId: companyId,
            financialYearId: targetFY.id,
            voucherTypeCode: original.voucherTypeCode,
            number: number,
            date: reversalDraft.date,
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
            let accountRepo = AccountRepository(db: tx)
            try vRepo.insert(reversal)
            try lRepo.insertBatch(flippedLines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherReversed,
                entityType: "voucher",
                entityId: reversalId.uuidString,
                snapshotBefore: VoucherAuditSnapshot(voucher: original, lines: originalLines),
                snapshotAfter: VoucherAuditSnapshot(voucher: reversal, lines: flippedLines),
                reason: reason
            )
            try markAccountsUsed(accountRepo, lines: flippedLines)
        }
        ReportService.invalidateCache(companyId: companyId)
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

    private func reversalFinancialYear(for originalFY: FinancialYear) throws -> FinancialYear {
        if !originalFY.isLocked {
            return originalFY
        }

        let openYears = try FinancialYearRepository(db: db).findOpenForCompany(companyId)
        guard let target = openYears.sorted(by: { $0.startDate > $1.startDate }).first else {
            throw AppError.businessRule("Cannot reverse voucher because there is no open financial year available.")
        }
        return target
    }

    private func markAccountsUsed(_ accountRepo: AccountRepository, lines: [LedgerLine]) throws {
        var seen: Set<Account.ID> = []
        seen.reserveCapacity(lines.count)
        for line in lines where seen.insert(line.accountId).inserted {
            try accountRepo.markUsed(line.accountId)
        }
    }
}
