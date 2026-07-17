import Foundation

public final class FinancialYearService: Sendable {

    public let db: SQLiteDatabase
    public let repository: FinancialYearRepository
    public let audit: AuditService

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = FinancialYearRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
    }

    public func list() throws -> [FinancialYear] {
        try repository.listForCompany(audit.companyId)
    }

    public func openYears() throws -> [FinancialYear] {
        try repository.findOpenForCompany(audit.companyId)
    }

    public func mostRecent() throws -> FinancialYear? {
        try repository.findMostRecent(audit.companyId)
    }

    public func create(label: String,
                       startDate: Date,
                       endDate: Date,
                       booksBeginDate: Date) throws -> FinancialYear {
        let input = FinancialYearInputValidator.Input(
            label: label, startDate: startDate, endDate: endDate,
            booksBeginDate: booksBeginDate
        )
        let result = FinancialYearInputValidator().validate(input)
        if case .invalid(let errs) = result {
            throw AppError.validation(errs[0])
        }
        let overlappingYears = try repository.overlaps(
            companyId: audit.companyId,
            startDate: startDate,
            endDate: endDate
        )
        guard overlappingYears.isEmpty else {
            let labels = overlappingYears.map(\.label).joined(separator: ", ")
            throw AppError.validation(.init(
                code: .financialYearOverlap,
                field: "startDate",
                message: "Financial year overlaps existing year(s): \(labels)."
            ))
        }
        let fy = FinancialYear(
            companyId: audit.companyId,
            label: label,
            startDate: startDate,
            endDate: endDate,
            booksBeginDate: booksBeginDate
        )
        try db.write { tx in
            let repo = FinancialYearRepository(db: tx)
            try repo.insert(fy)
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .financialYearCreated,
                entityType: "financial_year",
                entityId: fy.id.uuidString,
                snapshotAfter: fy
            )
        }
        return fy
    }

    public func lock(_ id: FinancialYear.ID, reason: String? = nil) throws {
        try db.write { tx in
            let repository = FinancialYearRepository(db: tx)
            guard let before = try repository.findById(id), before.companyId == audit.companyId else {
                throw AppError.notFound("Financial year")
            }
            try repository.lock(id)
            guard let after = try repository.findById(id) else { throw AppError.notFound("Financial year") }
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .financialYearLocked,
                entityType: "financial_year",
                entityId: id.uuidString,
                snapshotBefore: before,
                snapshotAfter: after,
                reason: reason
            )
        }
    }

    public func unlock(_ id: FinancialYear.ID, reason: String? = nil) throws {
        try db.write { tx in
            let repository = FinancialYearRepository(db: tx)
            guard let before = try repository.findById(id), before.companyId == audit.companyId else {
                throw AppError.notFound("Financial year")
            }
            try repository.unlock(id)
            guard let after = try repository.findById(id) else { throw AppError.notFound("Financial year") }
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .financialYearUnlocked,
                entityType: "financial_year",
                entityId: id.uuidString,
                snapshotBefore: before,
                snapshotAfter: after,
                reason: reason
            )
        }
    }

    public func close(_ id: FinancialYear.ID) throws {
        try db.write { tx in
            let repo = FinancialYearRepository(db: tx)
            guard let financialYear = try repo.findById(id), financialYear.companyId == audit.companyId else {
                throw AppError.notFound("Financial year")
            }
            if financialYear.isClosed {
                return
            }
            guard let targetFinancialYear = try repo.findNext(after: financialYear) else {
                throw AppError.businessRule("Create the next financial year before closing this year.")
            }

            let carryForwardRows = try closingBalanceRows(
                db: tx,
                sourceFinancialYear: financialYear,
                targetFinancialYear: targetFinancialYear,
                companyId: audit.companyId
            )

            try FinancialYearOpeningBalanceRepository(db: tx).replaceForFinancialYear(
                targetFinancialYear.id,
                rows: carryForwardRows
            )
            try repo.markClosed(id)
            guard let closedFinancialYear = try repo.findById(id) else {
                throw AppError.notFound("Financial year")
            }
            let audit = AuditService(db: tx, companyId: audit.companyId)
            try audit.record(
                action: .openingBalancePosted,
                entityType: "financial_year",
                entityId: targetFinancialYear.id.uuidString,
                reason: "Carry-forward from \(financialYear.label)"
            )
            try audit.record(
                action: .financialYearClosed,
                entityType: "financial_year",
                entityId: id.uuidString,
                snapshotBefore: financialYear,
                snapshotAfter: closedFinancialYear
            )
        }
    }

    public func reopen(_ id: FinancialYear.ID, reason: String? = nil) throws {
        try db.write { tx in
            let repo = FinancialYearRepository(db: tx)
            guard let financialYear = try repo.findById(id), financialYear.companyId == audit.companyId else {
                throw AppError.notFound("Financial year")
            }
            guard let targetFinancialYear = try repo.findNext(after: financialYear) else {
                throw AppError.businessRule("Next financial year is missing; reopen cannot verify carry-forward state.")
            }
            try FinancialYearOpeningBalanceRepository(db: tx).deleteForFinancialYear(targetFinancialYear.id)
            try repo.reopen(id)
            guard let reopened = try repo.findById(id) else { throw AppError.notFound("Financial year") }
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .financialYearReopened,
                entityType: "financial_year",
                entityId: id.uuidString,
                snapshotBefore: financialYear,
                snapshotAfter: reopened,
                reason: reason
            )
        }
    }

    private func closingBalanceRows(db: SQLiteDatabase,
                                    sourceFinancialYear: FinancialYear,
                                    targetFinancialYear: FinancialYear,
                                    companyId: Company.ID) throws -> [FinancialYearOpeningBalanceRepository.Row] {
        let accounts = try AccountRepository(db: db).listForCompany(companyId)
        let totalsByAccount = try ReportRepository(db: db).movementTotals(
            for: accounts.map(\.id),
            companyId: companyId,
            toDate: sourceFinancialYear.endDate
        )
        return try accounts.map { account in
            let movement = totalsByAccount[account.id]
            let debit = movement?.debitPaise ?? 0
            let credit = movement?.creditPaise ?? 0
            let signedOpening = try account.signedOpeningBalancePaise()
            let signedClosing = try CheckedMath.subtract(
                try CheckedMath.add(
                    signedOpening,
                    debit,
                    context: "calculating carry-forward debit component"
                ),
                credit,
                context: "calculating carry-forward closing balance"
            )
            let absoluteClosing = signedClosing < 0
                ? try CheckedMath.abs(signedClosing, context: "calculating carry-forward absolute credit")
                : signedClosing
            return FinancialYearOpeningBalanceRepository.Row(
                financialYearId: targetFinancialYear.id,
                sourceFinancialYearId: sourceFinancialYear.id,
                accountId: account.id,
                openingBalancePaise: absoluteClosing,
                openingBalanceSide: signedClosing < 0 ? .credit : .debit
            )
        }
    }
}
