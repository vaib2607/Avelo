import SwiftUI
import Observation

@MainActor
@Observable
public final class VoucherEditViewModel {

    public var draft: VoucherDraft
    public var accounts: [Account] = []
    public var validation: ValidationResult = .valid
    public var validationErrors: [ValidationError] = []
    public private(set) var isSubmitting: Bool = false
    public private(set) var localEditorError: AppError?
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
    public private(set) var company: Company?
    private var eligibilityPolicy = AccountEligibilityPolicy()

    // MARK: - Tally item-invoice mode (Sales/Purchase item-grid entry)
    //
    // Alternate to the ledger-line editor above: the user picks items and
    // quantities instead of ledger lines, and `ItemInvoiceService` computes
    // GST and posts both the ledger voucher and the item lines/stock
    // movements server-side. Only offered for Sales/Purchase.
    public var itemInvoiceMode: Bool = false {
        didSet { draft.entryMode = itemInvoiceMode ? .itemInvoice : .ledger }
    }
    public var items: [InventoryItem] = []
    public var salesOrPurchaseLedgerId: Account.ID?
    public var itemLines: [ItemLineRow] = [ItemLineRow()]

    public struct ItemLineRow: Identifiable, Equatable {
        public let id: UUID
        public var itemId: InventoryItem.ID?
        public var quantity: String
        public var rate: String

        public init(id: UUID = UUID(),
                    itemId: InventoryItem.ID? = nil,
                    quantity: String = "",
                    rate: String = "0.00") {
            self.id = id
            self.itemId = itemId
            self.quantity = quantity
            self.rate = rate
        }
    }

    public func addItemLine() { itemLines.append(ItemLineRow()) }

    public func removeItemLine(_ id: UUID) {
        itemLines.removeAll(where: { $0.id == id })
    }

    /// Item lines with both an item and a positive quantity picked; blank
    /// trailing rows (same UX as the ledger-line grid) are silently dropped.
    public func buildItemLineInputs() -> [ItemInvoiceService.ItemLineInput] {
        itemLines.compactMap(itemLineInput)
    }

    /// Shared by posting and keyboard traversal: zero-rate items are valid,
    /// but an item and positive whole quantity are required.
    public func itemLineInput(_ row: ItemLineRow) -> ItemInvoiceService.ItemLineInput? {
        guard let itemId = row.itemId,
              let qty = Int64(row.quantity.trimmingCharacters(in: .whitespaces)), qty > 0 else { return nil }
        return .init(itemId: itemId, quantity: qty, ratePaise: Currency.parseRupeeInput(row.rate) ?? 0)
    }

    public func isCompleteItemLine(_ row: ItemLineRow) -> Bool {
        itemLineInput(row) != nil
    }

    /// Returns the account field that should receive focus after a committed
    /// ledger amount. An incomplete row never grows the grid.
    public func advanceLedgerAfterCommittedAmount(lineId: UUID) -> UUID? {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return nil }
        let row = lines[index]
        guard row.accountId != nil,
              (Currency.parseRupeeInput(row.amount) ?? 0) != 0 else { return nil }
        if let nextBlank = lines[(index + 1)...].first(where: { $0.accountId == nil }) {
            return nextBlank.id
        }
        addLine()
        return lines.last?.id
    }

    /// Uses the same predicate as `buildItemLineInputs()`: an item and a
    /// positive whole quantity complete the row; zero rate remains valid.
    /// It returns the next item picker to focus and appends at most one row.
    public func advanceItemAfterCommittedRate(lineId: UUID) -> UUID? {
        guard let index = itemLines.firstIndex(where: { $0.id == lineId }),
              isCompleteItemLine(itemLines[index]) else { return nil }
        if let nextBlank = itemLines[(index + 1)...].first(where: { $0.itemId == nil }) {
            return nextBlank.id
        }
        addItemLine()
        return itemLines.last?.id
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

    public func eligibility(_ account: Account, for context: AccountSelectionContext) -> AccountEligibility {
        guard let company else {
            return AccountEligibility(isEligible: false, rejectionReason: "Company context is unavailable.")
        }
        return eligibilityPolicy.evaluate(account: account, for: context, company: company, groups: groups)
    }

    public func isCashOrBank(_ account: Account) -> Bool {
        eligibility(account, for: .bankReconciliation).isEligible
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
    /// Recovery/duplicate flows preserve their recorded entry mode. Contextual
    /// Ctrl+V is intentionally a fresh-entry shortcut, never a way to mutate
    /// a recovered draft unexpectedly.
    public private(set) var isRecoveredDraft: Bool = false

    /// Identity of this entry's autosaved draft row (AVL-P0-018). Stable for
    /// the lifetime of one "new voucher" sheet so repeated autosaves upsert
    /// the same row instead of accumulating one per keystroke pause; replaced
    /// with the recovered draft's own id in `loadFromRecoveredDraft` so
    /// continuing to edit a resumed draft keeps updating that same row.
    public private(set) var draftId: UUID = UUID()
    private var autosaveTask: Task<Void, Never>?
    private var draftPersistenceSuppressed = false
    private var cleanEditorSnapshot: EditorSnapshot?

    // MARK: - Undo/redo (AVL-P1-025)
    //
    // Memento-based over the existing EditorSnapshot type (already built for
    // dirty-state detection), not a per-field Command graph: fields here are
    // edited via direct two-way SwiftUI bindings, not intent-dispatching
    // methods, so a Command.apply()/undo() pair per keystroke doesn't fit
    // without a much larger UI rewrite. A checkpoint already fully describes
    // editor state, which is exactly what restore(_:) needs.
    //
    // Scoped to ledger-mode fields only (everything EditorSnapshot captures
    // except itemLines): EditorSnapshot.ItemLine only keeps itemId/quantity/
    // rate, fewer fields than the live ItemLineRow, so restoring item-invoice
    // mode from it would be lossy. Item-invoice undo is a documented gap,
    // not silently shipped incorrect.
    // A single history list plus a cursor, not separate undo/redo stacks:
    // every checkpoint call records "this is now the state" (uniformly
    // post-mutation), and undo/redo just walks the cursor. Two independent
    // stacks with mixed pre-mutation (addLine) and post-mutation (debounced
    // field edits) push semantics produced a real bug caught before writing
    // any tests: addLine's immediate pre-mutation push plus lines' onChange
    // scheduling a debounced post-mutation push for the same action created
    // a redundant history entry, making the first Cmd+Z visibly no-op. A
    // single index-walked history has only one semantic, so that class of
    // bug can't recur.
    private var undoHistory: [EditorSnapshot] = []
    private var undoHistoryIndex: Int = -1
    private var checkpointTask: Task<Void, Never>?
    private static let maxUndoHistoryDepth = 50

    public var canUndo: Bool { undoHistoryIndex > 0 }
    public var canRedo: Bool { undoHistoryIndex >= 0 && undoHistoryIndex < undoHistory.count - 1 }

    /// Records the current state as a checkpoint immediately (no debounce),
    /// called *after* the mutation — used by discrete structural actions
    /// like addLine()/removeLine() where the call site is already the
    /// natural boundary.
    private func recordUndoCheckpointNow() {
        checkpointTask?.cancel()
        checkpointTask = nil
        recordCheckpoint()
    }

    /// Debounced checkpoint for free-text-adjacent field edits (narration,
    /// amounts, dates, pickers) — mirrors scheduleAutosave()'s exact
    /// 800ms-pause-in-typing pattern so Cmd+Z coalesces into one step per
    /// pause rather than firing once per keystroke.
    public func scheduleCheckpoint() {
        checkpointTask?.cancel()
        checkpointTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.recordCheckpoint()
        }
    }

    private func recordCheckpoint() {
        let snapshot = editorSnapshot()
        if undoHistory.isEmpty {
            undoHistory = [snapshot]
            undoHistoryIndex = 0
            return
        }
        guard undoHistory[undoHistoryIndex] != snapshot else { return }
        // A new checkpoint after undoing invalidates everything the user
        // could have redone past this point.
        undoHistory.removeSubrange((undoHistoryIndex + 1)...)
        undoHistory.append(snapshot)
        undoHistoryIndex += 1
        if undoHistory.count > Self.maxUndoHistoryDepth {
            undoHistory.removeFirst()
            undoHistoryIndex -= 1
        }
    }

    public func undo() {
        guard canUndo else { return }
        undoHistoryIndex -= 1
        restore(undoHistory[undoHistoryIndex])
    }

    public func redo() {
        guard canRedo else { return }
        undoHistoryIndex += 1
        restore(undoHistory[undoHistoryIndex])
    }

    /// Clears history — called once the editor's session is over (posted
    /// successfully) so no lingering reference can offer "undo" into a now-
    /// immutable posted voucher. Posted history itself is never touched by
    /// undo/redo; this only discards the in-memory stack.
    public func sealUndoHistory() {
        checkpointTask?.cancel()
        checkpointTask = nil
        undoHistory.removeAll()
        undoHistoryIndex = -1
    }

    private func restore(_ snapshot: EditorSnapshot) {
        date = snapshot.date
        partyAccountId = snapshot.partyAccountId
        billReferenceType = snapshot.billReferenceType
        billReferenceNumber = snapshot.billReferenceNumber
        chequeNumber = snapshot.chequeNumber
        chequeDueDate = snapshot.chequeDueDate
        tdsSectionCode = snapshot.tdsSectionCode
        tdsTaxAmount = snapshot.tdsTaxAmount
        tcsSectionCode = snapshot.tcsSectionCode
        tcsTaxAmount = snapshot.tcsTaxAmount
        narration = snapshot.narration
        singleEntryMode = snapshot.singleEntryMode
        accountLedgerId = snapshot.accountLedgerId
        lines = snapshot.lines.map {
            LineRow(accountId: $0.accountId, amount: $0.amount, side: $0.side,
                    taxCode: $0.taxCode, costCenter: $0.costCenter)
        }
    }

    private struct EditorSnapshot: Equatable {
        struct LedgerLine: Equatable {
            let accountId: Account.ID?
            let amount: String
            let side: LedgerSide
            let taxCode: String?
            let costCenter: String?
        }

        struct ItemLine: Equatable {
            let itemId: InventoryItem.ID?
            let quantity: String
            let rate: String
        }

        let voucherTypeCode: VoucherType.Code
        let date: Date
        let partyAccountId: Account.ID?
        let billReferenceType: VoucherDraft.BillReferenceType?
        let billReferenceNumber: String
        let chequeNumber: String
        let chequeDueDate: Date?
        let tdsSectionCode: String
        let tdsTaxAmount: String
        let tcsSectionCode: String
        let tcsTaxAmount: String
        let narration: String
        let singleEntryMode: Bool
        let accountLedgerId: Account.ID?
        let lines: [LedgerLine]
        let itemInvoiceMode: Bool
        let salesOrPurchaseLedgerId: Account.ID?
        let itemLines: [ItemLine]
    }

    public init(companyId: Company.ID, db: SQLiteDatabase, fyId: FinancialYear.ID, initialType: VoucherType.Code, existingId: Voucher.ID? = nil) {
        self.companyId = companyId
        self.db = db
        self.fyId = fyId
        self.company = try? CompanyRepository(db: db).findById(companyId)
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

    /// Marks the fully configured editor as clean. Call this only after load
    /// or recovery has populated the raw UI text, so formatter output cannot
    /// cause a phantom dirty prompt.
    public func captureCleanEditorState() {
        let snapshot = editorSnapshot()
        cleanEditorSnapshot = snapshot
        // The same moment the dirty-tracking baseline is set is the correct
        // moment to seed undo history — undo must be able to return all the
        // way to this clean starting point, not just to the first edit.
        checkpointTask?.cancel()
        checkpointTask = nil
        undoHistory = [snapshot]
        undoHistoryIndex = 0
    }

    public func beginSubmission() -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        localEditorError = nil
        return true
    }

    public func endSubmission() {
        isSubmitting = false
    }

    public func setLocalEditorError(_ error: AppError) {
        localEditorError = error
    }

    public func clearLocalEditorError() {
        localEditorError = nil
    }

    /// Validates the current, already-flushed UI state without touching
    /// SQLite. The feature submission command is the sole caller that turns
    /// this draft into a financial write.
    public func prepareForSubmission() throws {
        if itemInvoiceMode {
            guard itemInvoiceValidationErrors.isEmpty else {
                throw AppError.businessRule(itemInvoiceValidationErrors[0])
            }
            return
        }
        revalidate()
        guard canPost else {
            throw AppError.validation(validationErrors.first ?? .init(
                code: .voucherDebitCreditMismatch,
                field: "voucher",
                message: "This voucher isn't ready to post yet."
            ))
        }
    }

    func focusTarget(for error: ValidationError) -> VoucherEditorFocusTarget {
        switch error.field {
        case "date": return .date
        case "party", "partyAccountId": return .party
        case "narration": return .narration
        case "accountLedgerId": return .accountLedger
        default:
            if let row = lines.first(where: { $0.accountId == nil }) ?? lines.first {
                return row.accountId == nil ? .ledgerAccount(row.id) : .ledgerAmount(row.id)
            }
            return .post
        }
    }

    func submissionFocusTarget() -> VoucherEditorFocusTarget {
        if itemInvoiceMode {
            if partyAccountId == nil { return .party }
            if salesOrPurchaseLedgerId == nil { return .salesPurchaseLedger }
            if let row = itemLines.first(where: { $0.itemId == nil }) { return .item(row.id) }
            if let row = itemLines.first(where: { itemLineInput($0) == nil }) { return .quantity(row.id) }
            return .post
        }
        if let error = validationErrors.first { return focusTarget(for: error) }
        return .post
    }

    public var hasUnsavedChanges: Bool {
        guard let cleanEditorSnapshot else { return hasMeaningfulCreateInput }
        return editorSnapshot() != cleanEditorSnapshot
    }

    /// Discards only this editor session. Create-mode scratch data is removed;
    /// edit mode never writes, deletes, or otherwise mutates posted history.
    public func discardUnsavedChanges() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if case .create = mode {
            deleteDraft()
        }
        cleanEditorSnapshot = editorSnapshot()
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
        self.company = try? CompanyRepository(db: db).findById(companyId)
        do {
            self.eligibilityPolicy = try AccountEligibilityPolicy.loading(db: db, companyId: companyId)
        } catch {
            self.validation = .invalid([ValidationError(
                code: .internal,
                field: "accounts",
                message: "Failed to load account eligibility: \(AppError.wrap(error).localizedMessage)"
            )])
        }
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

    /// Reloads the complete semantic account context after inline creation,
    /// regrouping, activation changes, or party-profile edits. Account rows,
    /// ancestor groups, company features, and explicit profiles must change as
    /// one snapshot or the picker and posting service can temporarily disagree.
    public func reloadAccountContext() throws {
        accounts = try AccountService(db: db, companyId: companyId).listActiveAccounts()
        groups = try AccountGroupRepository(db: db).listForCompany(companyId)
        company = try CompanyRepository(db: db).findById(companyId)
        eligibilityPolicy = try AccountEligibilityPolicy.loading(db: db, companyId: companyId)
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
        recordUndoCheckpointNow()
    }

    /// The natural (normal-balance) side for an account, used to pre-select
    /// a sensible Debit/Credit default the moment a user picks an account
    /// into a brand-new blank line, rather than always defaulting to Debit.
    public func suggestedSide(for accountId: Account.ID?) -> LedgerSide {
        guard let accountId,
              let account = accounts.first(where: { $0.id == accountId }),
              let group = groups.first(where: { $0.id == account.groupId })
        else { return .debit }
        return group.nature.normalBalance
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
        guard !draftPersistenceSuppressed else { return }
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

    /// Used when an editor is about to leave the view hierarchy. Unlike the
    /// debounce this captures the latest create-mode state synchronously so a
    /// route or sheet replacement cannot beat the 800 ms recovery timer.
    public func persistDraftImmediately() {
        guard case .create = mode else { return }
        guard !draftPersistenceSuppressed else { return }
        autosaveTask?.cancel()
        try? VoucherDraftRepository(db: db).upsert(currentDraftSnapshot())
    }

    /// Removes the autosaved draft. Called after a successful post (the
    /// draft is superseded by the real voucher) and on explicit cancel (the
    /// user chose to discard it) so drafts never outlive the session that
    /// created them except across a crash.
    public func deleteDraft() {
        draftPersistenceSuppressed = true
        autosaveTask?.cancel()
        autosaveTask = nil
        guard case .create = mode else { return }
        try? VoucherDraftRepository(db: db).delete(id: draftId)
    }

    /// Restores editor state from a previously autosaved draft, reusing its
    /// id so further autosaves continue updating the same row rather than
    /// creating a duplicate.
    public func loadFromRecoveredDraft(_ entry: VoucherEntryDraft) throws {
        draftPersistenceSuppressed = false
        isRecoveredDraft = true
        draftId = entry.id
        date = entry.date
        partyAccountId = entry.partyAccountId
        narration = entry.narration
        billReferenceType = entry.billReferenceType
        billReferenceNumber = entry.billReferenceNumber ?? ""
        chequeNumber = entry.chequeNumber ?? ""
        chequeDueDate = entry.chequeDueDate
        accountLedgerId = entry.accountLedgerId
        salesOrPurchaseLedgerId = entry.salesPurchaseLedgerId
        draft.entryMode = entry.entryMode
        draft.duplicatedFromVoucherId = entry.duplicatedFromVoucherId
        itemInvoiceMode = entry.entryMode == .itemInvoice
        let decoded = try decodeDraftLines(entry.linesJSON)
        if !decoded.isEmpty {
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
        if entry.entryMode == .itemInvoice {
            itemLines = try decodeItemLines(entry.itemLinesJSON)
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
            linesJSON: encodedLines,
            duplicatedFromVoucherId: voucher.id
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
            entryMode: draft.entryMode,
            date: date,
            partyAccountId: partyAccountId,
            narration: narration,
            billReferenceType: billReferenceType,
            billReferenceNumber: billReferenceNumber.isEmpty ? nil : billReferenceNumber,
            chequeNumber: chequeNumber.isEmpty ? nil : chequeNumber,
            chequeDueDate: chequeDueDate,
            accountLedgerId: accountLedgerId,
            salesPurchaseLedgerId: salesOrPurchaseLedgerId,
            linesJSON: encodedLines,
            itemLinesJSON: encodedItemLines(),
            updatedAt: Date()
        )
    }

    private func encodedItemLines() -> String? {
        guard itemInvoiceMode else { return nil }
        let rows = itemLines.map {
            DraftItemLineDTO(itemId: $0.itemId?.uuidString, quantity: $0.quantity, rate: $0.rate)
        }
        guard let data = try? JSONEncoder().encode(rows),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func decodeDraftLines(_ json: String) throws -> [DraftLineDTO] {
        guard let data = json.data(using: .utf8) else {
            throw AppError.validation(.init(code: .internal, field: "linesJSON", message: "Recovered voucher draft contains invalid ledger-line data."))
        }
        do {
            let rows = try JSONDecoder().decode([DraftLineDTO].self, from: data)
            for row in rows where row.accountId != nil && UUID(uuidString: row.accountId!) == nil {
                throw AppError.validation(.init(code: .internal, field: "linesJSON", message: "Recovered voucher draft contains an invalid account identifier."))
            }
            return rows
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.validation(.init(code: .internal, field: "linesJSON", message: "Recovered voucher draft contains malformed ledger-line data."))
        }
    }

    private func decodeItemLines(_ json: String?) throws -> [ItemLineRow] {
        guard let json else { return [ItemLineRow()] }
        guard let data = json.data(using: .utf8) else {
            throw AppError.validation(.init(code: .internal, field: "itemLinesJSON", message: "Recovered item invoice contains invalid item-line data."))
        }
        do {
            let rows = try JSONDecoder().decode([DraftItemLineDTO].self, from: data)
            let restored = try rows.map { row -> ItemLineRow in
                let itemId = try row.itemId.map {
                    guard let id = UUID(uuidString: $0) else {
                        throw AppError.validation(.init(code: .internal, field: "itemLinesJSON", message: "Recovered item invoice contains an invalid item identifier."))
                    }
                    return id
                }
                let quantity = row.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                if !quantity.isEmpty {
                    let exact = try ExactQuantity.parse(decimal: quantity)
                    guard !exact.isZero, exact.wholeValue != nil else {
                        throw AppError.validation(.init(code: .stockMovementQuantityZero, field: "quantity", message: "Recovered item invoice quantity must be a positive whole value."))
                    }
                }
                let rate = row.rate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rate.isEmpty, Currency.parseRupeeInput(rate) == nil {
                    throw AppError.validation(.init(code: .internal, field: "rate", message: "Recovered item invoice contains an invalid rate."))
                }
                return ItemLineRow(itemId: itemId, quantity: row.quantity, rate: row.rate)
            }
            return restored.isEmpty ? [ItemLineRow()] : restored
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.validation(.init(code: .internal, field: "itemLinesJSON", message: "Recovered item invoice contains malformed item-line data."))
        }
    }

    public func removeLine(_ id: UUID) {
        lines.removeAll(where: { $0.id == id })
        recordUndoCheckpointNow()
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

    private var hasMeaningfulCreateInput: Bool {
        !narration.isEmpty || partyAccountId != nil || accountLedgerId != nil ||
            !billReferenceNumber.isEmpty || !chequeNumber.isEmpty ||
            !tdsSectionCode.isEmpty || !tdsTaxAmount.isEmpty ||
            !tcsSectionCode.isEmpty || !tcsTaxAmount.isEmpty ||
            lines.contains { $0.accountId != nil || $0.amount != "0.00" } ||
            itemLines.contains { $0.itemId != nil || !$0.quantity.isEmpty || $0.rate != "0.00" }
    }

    private func editorSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            voucherTypeCode: draft.voucherTypeCode,
            date: normalizedDate(date),
            partyAccountId: partyAccountId,
            billReferenceType: billReferenceType,
            billReferenceNumber: billReferenceNumber,
            chequeNumber: chequeNumber,
            chequeDueDate: chequeDueDate.map(normalizedDate),
            tdsSectionCode: tdsSectionCode,
            tdsTaxAmount: tdsTaxAmount,
            tcsSectionCode: tcsSectionCode,
            tcsTaxAmount: tcsTaxAmount,
            narration: narration,
            singleEntryMode: singleEntryMode,
            accountLedgerId: accountLedgerId,
            lines: lines.map {
                .init(accountId: $0.accountId, amount: $0.amount, side: $0.side,
                      taxCode: $0.taxCode, costCenter: $0.costCenter)
            },
            itemInvoiceMode: itemInvoiceMode,
            salesOrPurchaseLedgerId: salesOrPurchaseLedgerId,
            itemLines: itemLines.map {
                .init(itemId: $0.itemId, quantity: $0.quantity, rate: $0.rate)
            }
        )
    }

    private func normalizedDate(_ value: Date) -> Date {
        DateFormatters.utcCalendar.startOfDay(for: value)
    }
}

extension VoucherEditViewModel: RouterDirtyStateProviding {}

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

private struct DraftItemLineDTO: Codable {
    let itemId: String?
    let quantity: String
    let rate: String
}
