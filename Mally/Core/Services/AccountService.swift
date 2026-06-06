import Foundation

public final class AccountService: Sendable {

    public let db: SQLiteDatabase
    public let repository: AccountRepository
    public let groupRepository: AccountGroupRepository
    public let audit: AuditService

    public init(db: SQLiteDatabase, companyId: Company.ID) {
        self.db = db
        self.repository = AccountRepository(db: db)
        self.groupRepository = AccountGroupRepository(db: db)
        self.audit = AuditService(db: db, companyId: companyId)
    }

    public func listAccounts() throws -> [Account] {
        try repository.listForCompany(audit.companyId)
    }

    public func listActiveAccounts() throws -> [Account] {
        try repository.listActiveForCompany(audit.companyId)
    }

    public func listGroups() throws -> [AccountGroup] {
        try groupRepository.listForCompany(audit.companyId)
    }

    public func listLeafGroups() throws -> [AccountGroup] {
        try groupRepository.listLeafGroupsForCompany(audit.companyId)
    }

    public func findAccount(_ id: Account.ID) throws -> Account? {
        try repository.findById(id)
    }

    public func findGroup(_ id: AccountGroup.ID) throws -> AccountGroup? {
        try groupRepository.findById(id)
    }

    public func createAccount(_ input: AccountInputValidator.Input) throws -> Account {
        let v = AccountInputValidator(db: db).validate(input, companyId: audit.companyId)
        if case .invalid(let errs) = v {
            throw AppError.validation(errs[0])
        }
        guard let gid = input.groupId else {
            throw AppError.validation(ValidationError(
                code: .accountGroupRequired, field: "group", message: "Group required."
            ))
        }
        let account = Account(
            companyId: audit.companyId,
            groupId: gid,
            code: input.code,
            name: input.name,
            openingBalancePaise: input.openingBalancePaise,
            openingBalanceSide: input.openingBalancePaise == 0 ? .debit : .debit,
            gstin: input.gstin
        )
        try db.write { tx in
            let repo = AccountRepository(db: tx)
            try repo.insert(account)
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .accountCreated,
                entityType: "account",
                entityId: account.id.uuidString,
                snapshotAfter: account
            )
        }
        return account
    }

    public func updateAccount(_ account: Account) throws {
        let before = try repository.findById(account.id)
        try db.write { tx in
            let repo = AccountRepository(db: tx)
            try repo.update(account)
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .accountUpdated,
                entityType: "account",
                entityId: account.id.uuidString,
                snapshotBefore: before,
                snapshotAfter: account
            )
        }
    }

    public func disableAccount(_ id: Account.ID) throws {
        guard let before = try repository.findById(id) else { throw AppError.notFound("Account") }
        try db.write { tx in
            let repo = AccountRepository(db: tx)
            try repo.disable(id)
            try AuditService(db: tx, companyId: audit.companyId).record(
                action: .accountDisabled,
                entityType: "account",
                entityId: id.uuidString,
                snapshotBefore: before
            )
        }
    }

    public func markUsed(_ id: Account.ID) throws {
        try repository.markUsed(id)
    }

    public func createGroup(code: String,
                            name: String,
                            nature: AccountNature,
                            parentGroupId: AccountGroup.ID? = nil) throws -> AccountGroup {
        let group = AccountGroup(
            companyId: audit.companyId,
            parentGroupId: parentGroupId,
            code: code,
            name: name,
            nature: nature
        )
        try groupRepository.insert(group)
        return group
    }
}
