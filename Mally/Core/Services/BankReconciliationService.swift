import Foundation

public final class BankReconciliationService: Sendable {

    public let db: SQLiteDatabase
    public let repository: BankReconciliationRepository
    public let audit: AuditService
    public let companyId: Company.ID

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = BankReconciliationRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
        self.companyId = companyId
    }

    public struct StatementEntry: Sendable, Codable, Identifiable {
        public let id: UUID
        public let date: Date
        public let amountPaise: Int64
        public let narration: String

        public init(id: UUID = UUID(), date: Date, amountPaise: Int64, narration: String) {
            self.id = id
            self.date = date
            self.amountPaise = amountPaise
            self.narration = narration
        }
    }

    public struct Match: Sendable, Codable, Identifiable {
        public let id: UUID
        public let statementEntry: StatementEntry
        public let voucherId: Voucher.ID
        public let voucherNumber: String
        public let voucherDate: Date
        public let voucherAmountPaise: Int64

        public init(id: UUID = UUID(),
                    statementEntry: StatementEntry,
                    voucherId: Voucher.ID,
                    voucherNumber: String,
                    voucherDate: Date,
                    voucherAmountPaise: Int64) {
            self.id = id
            self.statementEntry = statementEntry
            self.voucherId = voucherId
            self.voucherNumber = voucherNumber
            self.voucherDate = voucherDate
            self.voucherAmountPaise = voucherAmountPaise
        }
    }

    public struct ReconciliationResult: Sendable {
        public let asOf: Date
        public let matched: [Match]
        public let unmatchedStatement: [StatementEntry]
        public let bookBalancePaise: Int64
        public let bankBalancePaise: Int64
    }

    public func importStatement(accountId: Account.ID,
                                entries: [StatementEntry]) throws {
        try db.write { tx in
            let repo = BankReconciliationRepository(db: tx)
            for e in entries {
                try repo.insertStatementLine(
                    accountId: accountId,
                    date: e.date,
                    amountPaise: e.amountPaise,
                    narration: e.narration
                )
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .bankStatementImported,
                entityType: "bank_account",
                entityId: accountId.uuidString
            )
        }
    }

    public func reconcile(accountId: Account.ID,
                          asOf: Date,
                          tolerancePaise: Int64 = 0) throws -> ReconciliationResult {
        try db.write { tx in
            let repo = BankReconciliationRepository(db: tx)
            let bookBalance = try repo.bookBalance(accountId: accountId, asOf: asOf)
            let statement = try repo.statementLines(accountId: accountId, asOf: asOf)
            let vouchers = try repo.candidateVouchers(accountId: accountId, asOf: asOf)

            var matched: [Match] = []
            var matchedStatementIds: Set<UUID> = []
            var matchedVoucherIds: Set<Voucher.ID> = []

            for s in statement {
                if let v = vouchers.first(where: { v in
                    !matchedVoucherIds.contains(v.id)
                        && v.date == s.date
                        && abs(v.amountPaise - abs(s.amountPaise)) <= tolerancePaise
                }) {
                    matched.append(Match(
                        statementEntry: s,
                        voucherId: v.id,
                        voucherNumber: v.number,
                        voucherDate: v.date,
                        voucherAmountPaise: v.amountPaise
                    ))
                    matchedStatementIds.insert(s.id)
                    matchedVoucherIds.insert(v.id)
                }
            }
            let unmatched = statement.filter { !matchedStatementIds.contains($0.id) }
            let bankBalance = statement.reduce(Int64(0)) { $0 + $1.amountPaise }

            return ReconciliationResult(
                asOf: asOf,
                matched: matched,
                unmatchedStatement: unmatched,
                bookBalancePaise: bookBalance,
                bankBalancePaise: bankBalance
            )
        }
    }

    public func clearStatementLine(id: UUID) throws {
        try db.write { tx in
            let repo = BankReconciliationRepository(db: tx)
            try repo.clearStatementLine(id: id)
            try AuditService(db: tx, companyId: companyId).record(
                action: .bankStatementLineCleared,
                entityType: "bank_statement_line",
                entityId: id.uuidString
            )
        }
    }
}
