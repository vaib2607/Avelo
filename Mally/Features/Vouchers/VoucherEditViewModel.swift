import SwiftUI

@MainActor
public final class VoucherEditViewModel: ObservableObject {

    @Published public var draft: VoucherDraft
    @Published public var accounts: [Account] = []
    @Published public var validation: ValidationResult = .valid
    @Published public var validationErrors: [ValidationError] = []
    @Published public var narration: String = ""
    @Published public var reference: String = ""
    @Published public var date: Date = Date()
    @Published public var partyAccountId: Account.ID?
    @Published public var lines: [LineRow] = [LineRow()]

    public let mode: VoucherDraft.Mode
    public let companyId: Company.ID
    public let db: SQLiteDatabase
    public let fyId: FinancialYear.ID

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
                partyAccountId: nil, narration: "", reference: "",
                lines: []
            )
        } else {
            self.mode = .create
            self.draft = VoucherDraft(
                mode: .create,
                voucherTypeCode: initialType,
                date: Date(),
                partyAccountId: nil, narration: "", reference: "",
                lines: []
            )
        }
    }

    public struct LineRow: Identifiable {
        public let id = UUID()
        public var accountId: Account.ID?
        public var amount: String = "0.00"
        public var side: LedgerSide = .debit
        public var taxCode: String?
        public var costCenter: String?

        public init() {}
    }

    public func load(accounts: [Account], initialDate: Date) {
        self.accounts = accounts
        if case .edit(let vid) = mode {
            do {
                let svc = VoucherService(db: db, companyId: companyId)
                if let existing = try svc.findById(vid) {
                    self.draft = try svc.loadDraft(from: vid)
                    self.narration = existing.narration
                    self.reference = ""
                    self.date = existing.date
                    self.partyAccountId = existing.partyAccountId
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
        lines.append(LineRow())
    }

    public func removeLine(_ id: UUID) {
        lines.removeAll(where: { $0.id == id })
    }

    public var totalDebitPaise: Int64 {
        lines.filter { $0.side == .debit }
            .reduce(Int64(0)) { $0 + (Currency.parseRupeeInput($1.amount) ?? 0) }
    }

    public var totalCreditPaise: Int64 {
        lines.filter { $0.side == .credit }
            .reduce(Int64(0)) { $0 + (Currency.parseRupeeInput($1.amount) ?? 0) }
    }

    public var isBalanced: Bool { totalDebitPaise == totalCreditPaise && totalDebitPaise > 0 }

    public func buildDraft() -> VoucherDraft {
        var d = draft
        d.date = date
        d.partyAccountId = partyAccountId
        d.narration = narration
        d.reference = reference
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
