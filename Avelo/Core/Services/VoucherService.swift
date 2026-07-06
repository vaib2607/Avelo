import Foundation

public final class VoucherService: Sendable {

    private enum GSTRoundOffPolicy {
        static let ledgerCode = "ROUND_OFF"
        static let supportedVoucherTypes: Set<VoucherType.Code> = [.sales, .purchase, .creditNote, .debitNote]
        static let taxLedgerCodes: Set<String> = [
            "CGST_INPUT",
            "CGST_OUTPUT",
            "SGST_INPUT",
            "SGST_OUTPUT",
            "IGST_INPUT",
            "IGST_OUTPUT",
            "CESS"
        ]
        static let maxAutoBalanceDifferencePaise: UInt64 = 99
    }

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

        public var isEmpty: Bool {
            billAllocationKind == nil
                && billAllocationNumber == nil
                && chequeNumber == nil
                && chequeDueDate == nil
                && chequeStatus == nil
                && postDatedDate == nil
                && tdsSectionCode == nil
                && tdsTaxPaise == nil
                && tcsSectionCode == nil
                && tcsTaxPaise == nil
        }
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear) throws -> PostResult {
        defer { ReportService.invalidateCache(companyId: companyId) }
        return try postWithoutCacheInvalidation(draft: draft, in: fy)
    }

    public func post(draft: VoucherDraft, in fy: FinancialYear, workflow: WorkflowInputs) throws -> PostResult {
        guard workflow.isEmpty else {
            throw AppError.featureUnavailable("Bill, cheque, TDS, TCS, and post-dated voucher workflows are deferred outside the frozen schema.")
        }
        return try post(draft: draft, in: fy)
    }

    public func postBatch(_ drafts: [VoucherDraft], in fy: FinancialYear) throws -> [PostResult] {
        var results: [PostResult] = []
        results.reserveCapacity(drafts.count)
        let chunkSize = 500
        var index = drafts.startIndex
        while index < drafts.endIndex {
            let end = drafts.index(index, offsetBy: chunkSize, limitedBy: drafts.endIndex) ?? drafts.endIndex
            var chunkVouchers: [Voucher] = []
            chunkVouchers.reserveCapacity(drafts[index..<end].count)
            try db.write { _ in
                let sequenceRepo = VoucherSequenceRepository(db: db)
                let vRepo = VoucherRepository(db: db)
                let lRepo = LedgerLineRepository(db: db)
                let accountRepo = AccountRepository(db: db)
                var accountIdsToMark = Set<Account.ID>()
                var numbersByType: [VoucherType.Code: Array<String>.Iterator] = [:]
                for typeCode in Set(drafts[index..<end].map(\.voucherTypeCode)) {
                    let count = drafts[index..<end].filter { $0.voucherTypeCode == typeCode }.count
                    numbersByType[typeCode] = try sequenceRepo.nextNumbers(
                        companyId: companyId,
                        financialYearId: fy.id,
                        typeCode: typeCode,
                        count: count
                    ).makeIterator()
                }
                for draft in drafts[index..<end] {
                    let normalizedDraft = try normalizedDraftForPosting(draft, accountRepo: accountRepo)
                    let result = try validate(draft: normalizedDraft, in: fy)
                    if case .invalid(let errs) = result {
                        throw AppError.validation(errs[0])
                    }
                    let voucherId = UUID()
                    let now = Date()
                    let lines: [LedgerLine] = try normalizedDraft.filledLines.enumerated().map { idx, line in
                        guard let accountId = line.accountId else {
                            throw AppError.validation(.init(code: .internal, message: "Voucher line account is required"))
                        }
                        accountIdsToMark.insert(accountId)
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
                    guard var numbers = numbersByType[draft.voucherTypeCode], let number = numbers.next() else {
                        throw AppError.database(.rowReadFailed("missing reserved voucher number"))
                    }
                    numbersByType[draft.voucherTypeCode] = numbers
                    let voucher = Voucher(
                        id: voucherId,
                        companyId: companyId,
                        financialYearId: fy.id,
                        voucherTypeCode: normalizedDraft.voucherTypeCode,
                        number: number,
                        date: normalizedDraft.date,
                        partyAccountId: normalizedDraft.partyAccountId,
                        narration: normalizedDraft.narration,
                        isReversal: false,
                        reversalOfId: nil,
                        isPosted: true,
                        totalPaise: normalizedDraft.totalDebitPaise,
                        createdAt: now,
                        updatedAt: now
                    )
                    try vRepo.insert(voucher)
                    try lRepo.insertBatch(lines)
                    try AuditService(db: db, companyId: companyId).record(
                        action: .voucherPosted,
                        entityType: "voucher",
                        entityId: voucher.id.uuidString,
                        snapshotAfter: VoucherAuditSnapshot(voucher: voucher, lines: lines)
                    )
                    chunkVouchers.append(voucher)
                }
                try accountRepo.markUsedBatch(accountIdsToMark)
            }
            for voucher in chunkVouchers {
                results.append(PostResult(voucher: voucher, inventoryPrompt: try inventoryPromptContext(for: voucher)))
            }
            index = end
        }
        ReportService.invalidateCache(companyId: companyId)
        return results
    }

    private func postWithoutCacheInvalidation(draft: VoucherDraft, in fy: FinancialYear) throws -> PostResult {
        let normalizedDraft = try normalizedDraftForPosting(draft, accountRepo: AccountRepository(db: db))
        let result = try validate(draft: normalizedDraft, in: fy)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }

        let voucherId = UUID()
        let now = Date()
        let total = normalizedDraft.totalDebitPaise

        let lines: [LedgerLine] = try normalizedDraft.filledLines.enumerated().map { (idx, line) in
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
        var voucher: Voucher?
        try db.write { tx in
            let number = try VoucherSequenceRepository(db: tx).nextNumber(
                companyId: companyId,
                financialYearId: fy.id,
                typeCode: normalizedDraft.voucherTypeCode
            )
            let postedVoucher = Voucher(
                id: voucherId,
                companyId: companyId,
                financialYearId: fy.id,
                voucherTypeCode: normalizedDraft.voucherTypeCode,
                number: number,
                date: normalizedDraft.date,
                partyAccountId: normalizedDraft.partyAccountId,
                narration: normalizedDraft.narration,
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
            try vRepo.insert(postedVoucher)
            try lRepo.insertBatch(lines)
            try AuditService(db: tx, companyId: companyId).record(
                action: .voucherPosted,
                entityType: "voucher",
                entityId: postedVoucher.id.uuidString,
                snapshotAfter: VoucherAuditSnapshot(voucher: postedVoucher, lines: lines)
            )
            try markAccountsUsed(accountRepo, lines: lines)
            voucher = postedVoucher
        }

        guard let voucher else {
            throw AppError.validation(.init(code: .internal, message: "Voucher posting did not produce a voucher."))
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

    public func edit(_ voucherId: Voucher.ID, with newDraft: VoucherDraft, in fy: FinancialYear) throws -> Voucher {
        guard let existing = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard existing.companyId == companyId else {
            throw AppError.notFound("Voucher")
        }
        if existing.status == .cancelled {
            throw AppError.businessRule("Cancelled vouchers cannot be edited.")
        }
        guard let existingFY = try FinancialYearRepository(db: db).findById(existing.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        guard existingFY.companyId == companyId else {
            throw AppError.notFound("Financial year")
        }
        if existing.isReversal {
            throw AppError.businessRule("Reversal vouchers cannot be edited.")
        }
        if try repository.hasReversal(for: voucherId) {
            throw AppError.businessRule("This voucher has already been reversed and cannot be edited in place.")
        }
        let existingLines = try linesRepository.findForVoucher(voucherId)
        let normalizedDraft = try normalizedDraftForPosting(newDraft, accountRepo: AccountRepository(db: db))
        let result = try validate(draft: normalizedDraft, in: existingFY, existingVoucherId: voucherId)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        var updated = existing
        updated.date = normalizedDraft.date
        updated.partyAccountId = normalizedDraft.partyAccountId
        updated.narration = normalizedDraft.narration
        updated.totalPaise = normalizedDraft.totalDebitPaise
        updated.updatedAt = Date()
        let newLines: [LedgerLine] = try normalizedDraft.filledLines.enumerated().map { (idx, line) in
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
            try vRepo.update(updated)
            try lRepo.deleteForVoucher(voucherId)
            try lRepo.insertBatch(newLines)
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
        guard original.companyId == companyId else {
            throw AppError.notFound("Voucher")
        }
        if original.status == .cancelled {
            throw AppError.businessRule("Cancelled vouchers cannot be reversed again.")
        }
        guard let originalFY = try FinancialYearRepository(db: db).findById(original.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        guard originalFY.companyId == companyId else {
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

    public func cancel(_ voucherId: Voucher.ID,
                       reason: String,
                       actor: String = "user") throws -> Voucher {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw AppError.validation(.init(code: .internal, field: "reason", message: "Cancellation reason is required."))
        }
        guard let original = try repository.findById(voucherId) else {
            throw AppError.notFound("Voucher")
        }
        guard original.companyId == companyId else {
            throw AppError.notFound("Voucher")
        }
        guard original.status != .cancelled else {
            throw AppError.businessRule("This voucher has already been cancelled.")
        }
        guard !original.isReversal else {
            throw AppError.businessRule("Reversal vouchers cannot be cancelled.")
        }
        if try repository.hasReversal(for: voucherId) {
            throw AppError.businessRule("This voucher has already been reversed and cannot be cancelled safely.")
        }
        let originalLines = try linesRepository.findForVoucher(voucherId)
        let reversal = try createReversal(for: original, originalLines: originalLines, reason: "Cancellation: \(trimmedReason)")
        let flippedLines = buildFlippedLines(from: originalLines, reversalId: reversal.id)
        var cancelled = original
        cancelled.status = .cancelled
        cancelled.cancelledAt = reversal.createdAt
        cancelled.cancelledBy = actor
        cancelled.cancellationReason = trimmedReason
        cancelled.cancellationVoucherId = reversal.id
        cancelled.updatedAt = reversal.createdAt

        try db.write { tx in
            let vRepo = VoucherRepository(db: tx)
            let lRepo = LedgerLineRepository(db: tx)
            let accountRepo = AccountRepository(db: tx)
            try vRepo.insert(reversal)
            try lRepo.insertBatch(flippedLines)
            try vRepo.markCancelled(cancelled)
            let audit = AuditService(db: tx, companyId: companyId)
            try audit.record(
                action: .voucherReversed,
                entityType: "voucher",
                entityId: reversal.id.uuidString,
                snapshotBefore: VoucherAuditSnapshot(voucher: original, lines: originalLines),
                snapshotAfter: VoucherAuditSnapshot(voucher: reversal, lines: flippedLines),
                reason: "Cancellation: \(trimmedReason)"
            )
            try audit.record(
                action: .voucherCancelled,
                entityType: "voucher",
                entityId: cancelled.id.uuidString,
                snapshotBefore: VoucherAuditSnapshot(voucher: original, lines: originalLines),
                snapshotAfter: VoucherAuditSnapshot(voucher: cancelled, lines: originalLines),
                reason: trimmedReason
            )
            try markAccountsUsed(accountRepo, lines: flippedLines)
        }
        ReportService.invalidateCache(companyId: companyId)
        return cancelled
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

    public func count(filter: VoucherRepository.Filter) throws -> Int {
        try repository.count(filter: filter)
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
        guard voucher.companyId == companyId else {
            throw AppError.notFound("Voucher")
        }
        if voucher.status == .cancelled {
            throw AppError.businessRule("Cancelled vouchers cannot be loaded for editing.")
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
        guard originalFY.companyId == companyId else {
            throw AppError.notFound("Financial year")
        }
        if !originalFY.isLocked {
            return originalFY
        }

        let openYears = try FinancialYearRepository(db: db).findOpenForCompany(companyId)
        guard let target = openYears.sorted(by: { $0.startDate > $1.startDate }).first else {
            throw AppError.businessRule("Cannot reverse voucher because there is no open financial year available.")
        }
        return target
    }

    private func createReversal(for original: Voucher,
                                originalLines: [LedgerLine],
                                reason: String? = nil) throws -> Voucher {
        guard original.companyId == companyId else {
            throw AppError.notFound("Voucher")
        }
        guard let originalFY = try FinancialYearRepository(db: db).findById(original.financialYearId) else {
            throw AppError.notFound("Financial year")
        }
        guard originalFY.companyId == companyId else {
            throw AppError.notFound("Financial year")
        }
        let targetFY = try reversalFinancialYear(for: originalFY)
        let reversalId = UUID()
        let flippedLines = buildFlippedLines(from: originalLines, reversalId: reversalId)
        let number = try sequenceRepository.nextNumber(
            companyId: companyId,
            financialYearId: targetFY.id,
            typeCode: original.voucherTypeCode
        )
        let now = Date()
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
        return Voucher(
            id: reversalId,
            companyId: companyId,
            financialYearId: targetFY.id,
            voucherTypeCode: original.voucherTypeCode,
            number: number,
            date: reversalDate,
            partyAccountId: original.partyAccountId,
            narration: "Reversal of \(original.number)" + (reason.map { ": \($0)" } ?? ""),
            status: .open,
            isReversal: true,
            reversalOfId: original.id,
            isPosted: true,
            totalPaise: original.totalPaise,
            createdAt: now,
            updatedAt: now
        )
    }

    private func buildFlippedLines(from originalLines: [LedgerLine], reversalId: Voucher.ID) -> [LedgerLine] {
        originalLines.enumerated().map { (idx, line) in
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
    }

    private func markAccountsUsed(_ accountRepo: AccountRepository, lines: [LedgerLine]) throws {
        var seen: Set<Account.ID> = []
        seen.reserveCapacity(lines.count)
        for line in lines where seen.insert(line.accountId).inserted {
            try accountRepo.markUsed(line.accountId)
        }
    }

    private func normalizedDraftForPosting(_ draft: VoucherDraft,
                                           accountRepo: AccountRepository) throws -> VoucherDraft {
        guard GSTRoundOffPolicy.supportedVoucherTypes.contains(draft.voucherTypeCode) else {
            return draft
        }

        let roundOffAccount = try accountRepo.findByCode(GSTRoundOffPolicy.ledgerCode, companyId: companyId)
        let nonRoundOffLines = draft.lines.filter { line in
            guard let accountId = line.accountId else { return true }
            return accountId != roundOffAccount?.id
        }
        let normalizedWithoutRoundOff = VoucherDraft(
            mode: draft.mode,
            voucherTypeCode: draft.voucherTypeCode,
            date: draft.date,
            partyAccountId: draft.partyAccountId,
            billReferenceType: draft.billReferenceType,
            billReferenceNumber: draft.billReferenceNumber,
            narration: draft.narration,
            lines: reindexed(nonRoundOffLines)
        )

        let filledAccountIds = Set(normalizedWithoutRoundOff.filledLines.compactMap(\.accountId))
        guard !filledAccountIds.isEmpty else {
            return normalizedWithoutRoundOff
        }

        let accountById = try loadAccounts(ids: filledAccountIds, accountRepo: accountRepo)
        let containsGSTTaxLedger = normalizedWithoutRoundOff.filledLines.contains { line in
            guard let accountId = line.accountId,
                  let account = accountById[accountId] else {
                return false
            }
            return GSTRoundOffPolicy.taxLedgerCodes.contains(account.code)
        }
        guard containsGSTTaxLedger else {
            return draft
        }

        guard let roundOffAccount else {
            throw AppError.businessRule("GST round-off ledger '\(GSTRoundOffPolicy.ledgerCode)' is missing for this company.")
        }

        let totals = try normalizedWithoutRoundOff.checkedTotals()
        guard totals.difference != 0 else {
            return normalizedWithoutRoundOff
        }
        guard totals.difference.magnitude <= GSTRoundOffPolicy.maxAutoBalanceDifferencePaise else {
            return normalizedWithoutRoundOff
        }

        let roundOffAmount = Int64(totals.difference.magnitude)
        let roundOffSide: EntrySide = totals.difference > 0 ? .credit : .debit
        var balancedLines = normalizedWithoutRoundOff.lines
        balancedLines.append(
            VoucherDraft.Line(
                accountId: roundOffAccount.id,
                amountPaise: roundOffAmount,
                side: roundOffSide,
                taxCode: nil,
                costCenter: nil,
                lineOrder: balancedLines.count
            )
        )

        return VoucherDraft(
            mode: draft.mode,
            voucherTypeCode: draft.voucherTypeCode,
            date: draft.date,
            partyAccountId: draft.partyAccountId,
            billReferenceType: draft.billReferenceType,
            billReferenceNumber: draft.billReferenceNumber,
            narration: draft.narration,
            lines: reindexed(balancedLines)
        )
    }

    private func loadAccounts(ids: Set<Account.ID>,
                              accountRepo: AccountRepository) throws -> [Account.ID: Account] {
        var out: [Account.ID: Account] = [:]
        out.reserveCapacity(ids.count)
        for id in ids {
            guard let account = try accountRepo.findById(id) else {
                throw AppError.notFound("Account")
            }
            out[id] = account
        }
        return out
    }

    private func reindexed(_ lines: [VoucherDraft.Line]) -> [VoucherDraft.Line] {
        lines.enumerated().map { index, line in
            var updated = line
            updated.lineOrder = index
            return updated
        }
    }
}
