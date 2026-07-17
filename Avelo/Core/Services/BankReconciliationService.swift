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

    public typealias StatementEntry = BankReconciliationRepository.StatementLine

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
        let bankAccount = try requireReconcilableAccount(accountId)
        let fiscalLockChecker = FiscalLockChecker(db: db)
        for entry in entries where entry.companyId != companyId || entry.accountId != bankAccount.id {
            throw AppError.validation(.init(code: .voucherAccountInactive, field: "accountId", message: "Imported bank statement lines must belong to the active company and selected bank account."))
        }
        for entry in entries {
            _ = try fiscalLockChecker.assertDateOpen(entry.date, companyId: companyId, mutationLabel: "Bank statement date")
        }
        try db.write { tx in
            let repo = BankReconciliationRepository(db: tx)
            let importBatchId = UUID()
            for e in entries {
                try repo.insertStatementLine(
                    companyId: companyId,
                    accountId: accountId,
                    date: e.date,
                    amountPaise: e.amountPaise,
                    narration: e.narration,
                    importBatchId: importBatchId
                )
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .bankStatementImported,
                entityType: "bank_statement_import",
                entityId: importBatchId.uuidString,
                snapshotAfter: entries,
                reason: "\(entries.count) line(s) imported for account \(accountId.uuidString)"
            )
        }
    }

    public func reconcile(accountId: Account.ID,
                          asOf: Date,
                          tolerancePaise: Int64 = 0,
                          dateToleranceDays: Int = 3) throws -> ReconciliationResult {
        _ = try requireReconcilableAccount(accountId)
        let bookBalance: Int64
        let statement: [StatementEntry]
        let vouchers: [BankReconciliationRepository.VoucherCandidate]
        let matched: [Match]
        let unmatched: [StatementEntry]
        let bankBalance: Int64
        do {
            bookBalance = try repository.bookBalance(accountId: accountId, asOf: asOf)
            statement = try repository.statementLines(accountId: accountId, asOf: asOf)
            vouchers = try repository.candidateVouchers(accountId: accountId, asOf: asOf)

            var m: [Match] = []
            var matchedStatementIds: Set<UUID> = []
            var matchedVoucherIds: Set<Voucher.ID> = []

            for s in statement {
                if let v = vouchers.first(where: { v in
                    guard !matchedVoucherIds.contains(v.id),
                          Self.isWithinDateTolerance(v.date, s.date, days: dateToleranceDays) else {
                        return false
                    }
                    guard let statementMagnitude = try? CheckedMath.abs(s.amountPaise, context: "matching bank statement amount"),
                          let delta = try? CheckedMath.subtract(v.amountPaise, statementMagnitude, context: "matching bank statement delta"),
                          let deltaMagnitude = try? CheckedMath.abs(delta, context: "matching bank statement delta") else {
                        return false
                    }
                    return deltaMagnitude <= tolerancePaise
                }) {
                    m.append(Match(
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
            matched = m
            unmatched = statement.filter { !matchedStatementIds.contains($0.id) }
            bankBalance = try CheckedMath.sum(statement.map(\.amountPaise), context: "summing bank statement balance")
        }
        return ReconciliationResult(
            asOf: asOf,
            matched: matched,
            unmatchedStatement: unmatched,
            bookBalancePaise: bookBalance,
            bankBalancePaise: bankBalance
        )
    }

    public func clearStatementLine(id: UUID) throws {
        guard let line = try repository.findStatementLine(id: id), line.companyId == companyId else {
            throw AppError.notFound("Bank statement line")
        }
        _ = try FiscalLockChecker(db: db).assertDateOpen(line.date, companyId: companyId, mutationLabel: "Bank statement date")
        try db.write { tx in
            let repo = BankReconciliationRepository(db: tx)
            try repo.clearStatementLine(id: id)
            guard let cleared = try repo.findStatementLine(id: id) else {
                throw AppError.notFound("Bank statement line")
            }
            try AuditService(db: tx, companyId: companyId).record(
                action: .bankStatementLineCleared,
                entityType: "bank_statement_line",
                entityId: id.uuidString,
                snapshotBefore: line,
                snapshotAfter: cleared
            )
        }
    }

    private func requireReconcilableAccount(_ accountId: Account.ID) throws -> Account {
        guard let company = try CompanyRepository(db: db).findById(companyId),
              let account = try AccountRepository(db: db).findById(accountId) else {
            throw AppError.notFound("Account")
        }
        let eligibility = try AccountEligibilityPolicy.loading(db: db, companyId: companyId).evaluate(
            account: account,
            for: .bankReconciliation,
            company: company,
            groups: try AccountGroupRepository(db: db).listForCompany(companyId)
        )
        guard eligibility.isEligible else {
            throw AppError.validation(.init(
                code: .voucherAccountInactive,
                field: "accountId",
                message: eligibility.rejectionReason ?? "Account is not eligible for bank reconciliation."
            ))
        }
        return account
    }

    private static func isWithinDateTolerance(_ lhs: Date, _ rhs: Date, days: Int) -> Bool {
        let allowedDays = max(0, days)
        let calendar = DateFormatters.utcCalendar
        let start = calendar.startOfDay(for: lhs)
        let end = calendar.startOfDay(for: rhs)
        let delta = calendar.dateComponents([.day], from: start, to: end).day ?? Int.max
        return isDeltaWithinTolerance(deltaDays: delta, allowedDays: allowedDays)
    }

    static func isDeltaWithinTolerance(deltaDays: Int, allowedDays: Int) -> Bool {
        let clampedTolerance = max(0, allowedDays)
        if deltaDays >= 0 {
            return deltaDays <= clampedTolerance
        }
        return deltaDays >= -clampedTolerance
    }
}
