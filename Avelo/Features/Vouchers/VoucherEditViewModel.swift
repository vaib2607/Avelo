import SwiftUI
import Observation

@MainActor
@Observable
public final class VoucherEditViewModel {

    public var draft: VoucherDraft
    public var accounts: [Account] = []
    public var validation: ValidationResult = .valid
    public var validationErrors: [ValidationError] = []
    public var narration: String = ""
    public var date: Date = Date()
    public var partyAccountId: Account.ID?
    public var billReferenceType: VoucherDraft.BillReferenceType?
    public var billReferenceNumber: String = ""
    public var chequeNumber: String = ""
    public var chequeDueDate: Date?
    public var tdsSectionCode: String = ""
    public var tdsTaxAmount: String = ""
    public var tcsSectionCode: String = ""
    public var tcsTaxAmount: String = ""
    public var lines: [LineRow] = [LineRow()]

    // MARK: - Narration recall (AVL-P2-012, Ctrl+R)
    public var narrationSuggestions: [String] = []

    public func loadNarrationSuggestions() {
        narrationSuggestions = (try? VoucherRepository(db: db).recentNarrations(companyId: companyId)) ?? []
    }

    // MARK: - Tally single-entry mode (Contra F4 / Payment F5 / Receipt F6)
    //
    // In single-entry mode the top "Account" field holds the cash/bank ledger
    // and `lines` holds only the particulars (counter-ledgers). `buildDraft()`
    // composes the balancing account line, so posting and validation are
    // unchanged from double entry.
    public var singleEntryMode: Bool = false
    public var accountLedgerId: Account.ID?
    public var groups: [AccountGroup] = []

    // MARK: - Tally item-invoice mode (Sales/Purchase item-grid entry)
    //
    // Alternate to the ledger-line editor above: the user picks items and
    // quantities instead of ledger lines, and `ItemInvoiceService` computes
    // GST and posts both the ledger voucher and the item lines/stock
    // movements server-side. Only offered for Sales/Purchase.
    public var itemInvoiceMode: Bool = false
    public var items: [InventoryItem] = []
    public var salesOrPurchaseLedgerId: Account.ID?
    public var itemLines: [ItemLineRow] = [ItemLineRow()]

    public struct ItemLineRow: Identifiable, Equatable {
        public let id = UUID()
        public var itemId: InventoryItem.ID?
        public var quantity: String = ""
        public var rate: String = "0.00"

        public init() {}
    }

    public func addItemLine() { itemLines.append(ItemLineRow()) }

    public func removeItemLine(_ id: UUID) {
        itemLines.removeAll(where: { $0.id == id })
    }

    /// Item lines with both an item and a positive quantity picked; blank
    /// trailing rows (same UX as the ledger-line grid) are silently dropped.
    public func buildItemLineInputs() -> [ItemInvoiceService.ItemLineInput] {
        itemLines.compactMap { row in
            guard let itemId = row.itemId,
                  let qty = Int64(row.quantity.trimmingCharacters(in: .whitespaces)), qty > 0 else { return nil }
            let rate = Currency.parseRupeeInput(row.rate) ?? 0
            return .init(itemId: itemId, quantity: qty, ratePaise: rate)
        }
    }

    public var itemInvoiceValidationErrors: [String] {
        var errors: [String] = []
        if partyAccountId == nil { errors.append("Select a party account.") }
        if salesOrPurchaseLedgerId == nil { errors.append("Select the sales/purchase ledger.") }
        if buildItemLineInputs().isEmpty { errors.append("Add at least one item line with a quantity.") }
        return errors
    }

    public var canPostItemInvoice: Bool { itemInvoiceValidationErrors.isEmpty }

    /// Side of the top "Account" ledger per Tally: Contra debits the
    /// destination, Receipt debits the receiving cash/bank, Payment credits
    /// the paying cash/bank.
    public var accountSide: LedgerSide {
        switch draft.voucherTypeCode {
        case .payment: return .credit
        default:       return .debit
        }
    }

    public var particularsSide: LedgerSide {
        accountSide == .debit ? .credit : .debit
    }

    /// Tally classifies contra-eligible ledgers by group (Cash-in-Hand, Bank
    /// Accounts, Bank OD). Avelo's legacy seed keeps cash as a ledger under
    /// Current Assets, so the account-level flags are checked too.
    public func isCashOrBank(_ account: Account) -> Bool {
        if account.isBankAccount { return true }
        if account.code == "CASH_IN_HAND" { return true }
        if account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare("Cash", options: .caseInsensitive) == .orderedSame {
            return true
        }
        if let group = groups.first(where: { $0.id == account.groupId }) {
            return ["BANK_ACCOUNTS", "CASH_IN_HAND", "BANK_OD"].contains(group.code)
        }
        return false
    }

    public var particularsTotalPaise: Int64 {
        (try? CheckedMath.sum(
            lines.lazy.map { Currency.parseRupeeInput($0.amount) ?? 0 },
            context: "summing single-entry particulars"
        )) ?? 0
    }

    public let mode: VoucherDraft.Mode
    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID

    /// Identity of this entry's autosaved draft row (AVL-P0-018). Stable for
    /// the lifetime of one "new voucher" sheet so repeated autosaves upsert
    /// the same row instead of accumulating one per keystroke pause; replaced
    /// with the recovered draft's own id in `loadFromRecoveredDraft` so
    /// continuing to edit a resumed draft keeps updating that same row.
    public private(set) var draftId: UUID = UUID()
    private var autosaveTask: Task<Void, Never>?

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID, initialType: VoucherType.Code, existingId: Voucher.ID? = nil) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
        if let eid = existingId {
            self.mode = .edit(originalVoucherId: eid)
                self.draft = VoucherDraft(
                    mode: .edit(originalVoucherId: eid),
                    voucherTypeCode: initialType,
                    date: Date(),
                    partyAccountId: nil, narration: "",
                    lines: []
                )
        } else {
            self.mode = .create
            self.draft = VoucherDraft(
                mode: .create,
                voucherTypeCode: initialType,
                date: Date(),
                partyAccountId: nil, narration: "",
                lines: []
            )
        }
    }

    public struct LineRow: Identifiable, Equatable {
        public let id = UUID()
        public var accountId: Account.ID?
        public var amount: String = "0.00"
        public var side: LedgerSide = .debit
        public var taxCode: String?
        public var costCenter: String?

        public init() {}

        public init(accountId: Account.ID?,
                    amount: String,
                    side: LedgerSide,
                    taxCode: String? = nil,
                    costCenter: String? = nil) {
            self.accountId = accountId
            self.amount = amount
            self.side = side
            self.taxCode = taxCode
            self.costCenter = costCenter
        }
    }

    public func load(accounts: [Account], groups: [AccountGroup] = [], initialDate: Date) {
        self.accounts = accounts
        self.groups = groups
        if case .edit(let vid) = mode {
            do {
                let svc = VoucherService(db: db, companyId: companyId)
                if let existing = try svc.findById(vid) {
                    self.draft = try svc.loadDraft(from: vid)
                    let workflow = try AccountingWorkflowsRepository(db: db).workflowInputs(for: vid)
                    self.narration = existing.narration
                    self.date = existing.date
                    self.partyAccountId = existing.partyAccountId
                    self.billReferenceType = draft.billReferenceType
                    self.billReferenceNumber = draft.billReferenceNumber ?? ""
                    self.chequeNumber = workflow.chequeNumber ?? ""
                    self.chequeDueDate = workflow.chequeDueDate
                    let lines = try svc.lines(for: vid)
                    self.lines = lines.enumerated().map { (idx, l) in
                        LineRow(
                            accountId: l.accountId,
                            amount: Currency.formatAmountInput(paise: l.amountPaise),
                            side: l.side,
                            taxCode: l.taxCode,
                            costCenter: l.costCenter
                        )
                    }
                }
            } catch {
                self.validation = .invalid([ValidationError(code: .internal, field: nil, message: "Failed to load voucher: \(error)")])
            }
        } else {
            self.date = initialDate
        }
    }

    public func addLine() {
        var row = LineRow()
        // Tally pre-fills the balancing amount on the next line.
        if !singleEntryMode {
            let diff = (try? CheckedMath.subtract(totalDebitPaise, totalCreditPaise, context: "suggesting balancing amount")) ?? 0
            if diff != 0 {
                row.side = diff > 0 ? .credit : .debit
                row.amount = Currency.formatAmountInput(paise: abs(diff))
            }
        }
        lines.append(row)
    }

    public func pasteTSV(_ text: String) {
        let parsed = text.split(whereSeparator: \.isNewline).compactMap { row -> LineRow? in
            let cols = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3 else { return nil }
            let side = (cols[safe: 1]?.lowercased() == "cr") ? LedgerSide.credit : .debit
            return LineRow(
                accountId: nil,
                amount: cols[safe: 2] ?? "0.00",
                side: side,
                taxCode: cols[safe: 3],
                costCenter: cols[safe: 4]
            )
        }
        if !parsed.isEmpty {
            lines = parsed
        }
    }

    public func saveTemplate(named name: String) throws {
        try VoucherTemplateService(db: db, companyId: companyId).save(name: name, draft: buildDraft())
    }

    public func loadTemplate(named name: String) throws {
        if let loaded = try VoucherTemplateService(db: db, companyId: companyId).load(name: name) {
            draft = loaded
            narration = loaded.narration
            date = loaded.date
            partyAccountId = loaded.partyAccountId
            billReferenceType = loaded.billReferenceType
            billReferenceNumber = loaded.billReferenceNumber ?? ""
            lines = loaded.lines.map { LineRow(accountId: $0.accountId, amount: $0.amount, side: $0.side, taxCode: $0.taxCode, costCenter: $0.costCenter) }
        }
    }

    // MARK: - Draft autosave and crash recovery (AVL-P0-018)
    //
    // Only `.create` mode autosaves. An `.edit` session's underlying voucher
    // already exists and survives a crash intact; only its in-flight edits
    // would be lost, which is a smaller and separately-scoped risk than
    // losing an entire unsaved new voucher.

    /// Debounced autosave, called from the editor's field-change hooks.
    /// Waits for a short pause in typing before persisting, so a fast typist
    /// does not trigger a database write on every keystroke.
    public func scheduleAutosave() {
        guard case .create = mode else { return }
        autosaveTask?.cancel()
        let snapshot = currentDraftSnapshot()
        let db = self.db
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            // Autosave is best-effort scratch state, not a financial write;
            // a failure here must never surface as a user-facing error.
            try? VoucherDraftRepository(db: db).upsert(snapshot)
        }
    }

    /// Removes the autosaved draft. Called after a successful post (the
    /// draft is superseded by the real voucher) and on explicit cancel (the
    /// user chose to discard it) so drafts never outlive the session that
    /// created them except across a crash.
    public func deleteDraft() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard case .create = mode else { return }
        try? VoucherDraftRepository(db: db).delete(id: draftId)
    }

    /// Restores editor state from a previously autosaved draft, reusing its
    /// id so further autosaves continue updating the same row rather than
    /// creating a duplicate.
    public func loadFromRecoveredDraft(_ entry: VoucherEntryDraft) {
        draftId = entry.id
        date = entry.date
        partyAccountId = entry.partyAccountId
        narration = entry.narration
        billReferenceType = entry.billReferenceType
        billReferenceNumber = entry.billReferenceNumber ?? ""
        chequeNumber = entry.chequeNumber ?? ""
        chequeDueDate = entry.chequeDueDate
        accountLedgerId = entry.accountLedgerId
        if let data = entry.linesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DraftLineDTO].self, from: data),
           !decoded.isEmpty {
            let recoveredLines: [DraftLineDTO]
            if entry.accountLedgerId == nil,
               let sourceIndex = Self.singleEntrySourceIndex(
                   for: entry.voucherTypeCode,
                   in: decoded
               ),
               let sourceID = decoded[sourceIndex].accountId.flatMap(UUID.init(uuidString:)) {
                // Older duplicate drafts contained every posted line. Recover
                // them as the single-entry editor expects: the type-specific
                // cash/bank line becomes Account and only particulars remain.
                accountLedgerId = sourceID
                recoveredLines = decoded.enumerated().compactMap { index, line in
                    index == sourceIndex ? nil : line
                }
            } else {
                recoveredLines = decoded
            }
            if !recoveredLines.isEmpty {
                lines = recoveredLines.map {
                    LineRow(
                        accountId: $0.accountId.flatMap(UUID.init(uuidString:)),
                        amount: $0.amount,
                        side: $0.side == "credit" ? .credit : .debit,
                        taxCode: $0.taxCode,
                        costCenter: $0.costCenter
                    )
                }
            }
        }
    }

    /// AVL-P2-011 (duplicate voucher, Alt+2): builds a `VoucherEntryDraft`
    /// from an existing posted voucher's lines, reusing the same
    /// `pendingDraftRecovery` / `loadFromRecoveredDraft` path draft-crash-
    /// recovery already uses to preload a freshly-opened `NewVoucherSheet`.
    /// A fresh id keeps it independent of the source voucher's own
    /// (nonexistent) draft row — this never touches `avelo_voucher_drafts`.
    public static func duplicateDraft(from voucher: Voucher, lines: [LedgerLine]) -> VoucherEntryDraft {
        let sourceLine = singleEntrySourceLine(
            for: voucher.voucherTypeCode,
            in: lines,
            isReversal: voucher.isReversal
        )
        let counterpartLines = sourceLine.map { source in
            lines.filter { $0.id != source.id }
        } ?? lines
        let encodedLines = (try? JSONEncoder().encode(counterpartLines.map {
            DraftLineDTO(accountId: $0.accountId.uuidString, amount: Currency.formatAmountInput(paise: $0.amountPaise), side: $0.side.rawValue, taxCode: $0.taxCode, costCenter: $0.costCenter)
        })).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return VoucherEntryDraft(
            companyId: voucher.companyId,
            voucherTypeCode: voucher.voucherTypeCode,
            date: voucher.date,
            partyAccountId: voucher.partyAccountId,
            narration: voucher.narration,
            accountLedgerId: sourceLine?.accountId,
            linesJSON: encodedLines
        )
    }

    /// Payment stores the paying cash/bank ledger on credit; Receipt and
    /// Contra store their receiving/destination cash/bank ledger on debit.
    /// New single-entry vouchers use this convention to identify the cash/bank
    /// line while copying only its counterpart lines into the draft.
    private static func singleEntrySourceLine(for type: VoucherType.Code,
                                              in lines: [LedgerLine],
                                              isReversal: Bool) -> LedgerLine? {
        guard let side = singleEntryAccountSide(for: type, isReversal: isReversal) else { return nil }
        return lines.sorted { $0.lineOrder < $1.lineOrder }.first { $0.side == side }
    }

    private static func singleEntrySourceIndex(for type: VoucherType.Code,
                                               in lines: [DraftLineDTO]) -> Int? {
        guard let side = singleEntryAccountSide(for: type, isReversal: false) else { return nil }
        return lines.firstIndex {
            $0.side == side.rawValue && $0.accountId.flatMap(UUID.init(uuidString:)) != nil
        }
    }

    private static func singleEntryAccountSide(for type: VoucherType.Code,
                                               isReversal: Bool) -> LedgerSide? {
        let normalSide: LedgerSide
        switch type {
        case .payment:
            normalSide = .credit
        case .receipt, .contra:
            normalSide = .debit
        default:
            return nil
        }
        return isReversal ? (normalSide == .debit ? .credit : .debit) : normalSide
    }

    private func currentDraftSnapshot() -> VoucherEntryDraft {
        let encodedLines = (try? JSONEncoder().encode(lines.map {
            DraftLineDTO(accountId: $0.accountId?.uuidString, amount: $0.amount, side: $0.side.rawValue, taxCode: $0.taxCode, costCenter: $0.costCenter)
        })).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return VoucherEntryDraft(
            id: draftId,
            companyId: companyId,
            voucherTypeCode: draft.voucherTypeCode,
            date: date,
            partyAccountId: partyAccountId,
            narration: narration,
            billReferenceType: billReferenceType,
            billReferenceNumber: billReferenceNumber.isEmpty ? nil : billReferenceNumber,
            chequeNumber: chequeNumber.isEmpty ? nil : chequeNumber,
            chequeDueDate: chequeDueDate,
            accountLedgerId: accountLedgerId,
            linesJSON: encodedLines,
            updatedAt: Date()
        )
    }

    public func removeLine(_ id: UUID) {
        lines.removeAll(where: { $0.id == id })
    }

    public var totalDebitPaise: Int64 {
        (try? CheckedMath.sum(
            lines.lazy.filter { $0.side == .debit }.map { Currency.parseRupeeInput($0.amount) ?? 0 },
            context: "summing voucher editor debit lines"
        )) ?? 0
    }

    public var totalCreditPaise: Int64 {
        (try? CheckedMath.sum(
            lines.lazy.filter { $0.side == .credit }.map { Currency.parseRupeeInput($0.amount) ?? 0 },
            context: "summing voucher editor credit lines"
        )) ?? 0
    }

    public var isBalanced: Bool {
        if singleEntryMode {
            return accountLedgerId != nil && particularsTotalPaise > 0
        }
        return totalDebitPaise == totalCreditPaise && totalDebitPaise > 0
    }

    public func buildDraft() -> VoucherDraft {
        var d = draft
        d.date = date
        d.partyAccountId = partyAccountId
        d.billReferenceType = billReferenceType
        d.billReferenceNumber = billReferenceNumber.isEmpty ? nil : billReferenceNumber
        d.narration = narration
        if singleEntryMode {
            // Account line first (as Tally displays it), then particulars with
            // the side forced — the composed voucher balances by construction.
            var composed: [VoucherDraft.Line] = [
                VoucherDraft.Line(
                    accountId: accountLedgerId,
                    amountPaise: particularsTotalPaise,
                    side: accountSide,
                    taxCode: nil,
                    costCenter: nil,
                    lineOrder: 0
                )
            ]
            composed += lines.enumerated().map { (idx, row) in
                VoucherDraft.Line(
                    accountId: row.accountId,
                    amountPaise: Currency.parseRupeeInput(row.amount) ?? 0,
                    side: particularsSide,
                    taxCode: row.taxCode,
                    costCenter: row.costCenter,
                    lineOrder: idx + 1
                )
            }
            d.lines = composed
            return d
        }
        d.lines = lines.enumerated().map { (idx, row) in
            VoucherDraft.Line(
                accountId: row.accountId,
                amountPaise: Currency.parseRupeeInput(row.amount) ?? 0,
                side: row.side,
                taxCode: row.taxCode,
                costCenter: row.costCenter,
                lineOrder: idx
            )
        }
        return d
    }

    public func buildWorkflowInputs() -> VoucherService.WorkflowInputs {
        var workflow = VoucherService.WorkflowInputs()
        workflow.billAllocationKind = billReferenceType.map {
            switch $0 {
            case .newRef: return .newRef
            case .agstRef: return .agstRef
            case .advance: return .advance
            case .onAccount: return .onAccount
            }
        }
        workflow.billAllocationNumber = billReferenceNumber.isEmpty ? nil : billReferenceNumber
        workflow.chequeNumber = chequeNumber.isEmpty ? nil : chequeNumber
        workflow.chequeDueDate = chequeDueDate
        // AVL-P0 live bug: Currency.parseRupeeInput("") returns 0, not nil —
        // VoucherService.post(draft:in:workflow:) gates ALL posting on
        // tdsTaxPaise/tcsTaxPaise being nil (TDS/TCS is deferred outside the
        // frozen schema), so leaving these as Optional(0) for every voucher
        // that never touches TDS/TCS (i.e. nearly every voucher) made Post
        // throw "Feature unavailable" unconditionally. Must nil out on an
        // empty string exactly like the section-code fields already do.
        workflow.tdsSectionCode = tdsSectionCode.isEmpty ? nil : tdsSectionCode
        workflow.tdsTaxPaise = tdsTaxAmount.isEmpty ? nil : Currency.parseRupeeInput(tdsTaxAmount)
        workflow.tcsSectionCode = tcsSectionCode.isEmpty ? nil : tcsSectionCode
        workflow.tcsTaxPaise = tcsTaxAmount.isEmpty ? nil : Currency.parseRupeeInput(tcsTaxAmount)
        return workflow
    }

    public func revalidate() {
        let svc = ValidationService()
        let result = svc.validate(voucherDraft: buildDraft(), db: db,
                                  companyId: companyId, financialYearId: fyId,
                                  existingVoucherId: mode.originalVoucherId)
        self.validation = result
        if case .invalid(let errs) = result {
            self.validationErrors = errs
        } else {
            self.validationErrors = []
        }
    }

    public var canPost: Bool {
        if case .valid = validation { return isBalanced }
        return false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct DraftLineDTO: Codable {
    let accountId: String?
    let amount: String
    let side: String
    let taxCode: String?
    let costCenter: String?
}
