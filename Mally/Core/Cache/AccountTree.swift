import Foundation

/// Composite-pattern in-memory tree of account groups and ledgers for a single company.
///
/// Built from `AccountGroupRepository.listForCompany` + `AccountRepository.listForCompany`.
/// Balances are computed by walking the tree bottom-up: a `Ledger` node's balance is
/// `openingBalance + sum(debits) - sum(credits)`; a `Group` node's balance is the sum of
/// its children's balances.
///
/// The tree is immutable from the public API; mutation happens by replacing the whole
/// tree (see `AccountTreeCache`).
public struct AccountTree: Sendable {

    public let companyId: Company.ID
    public let builtAt: Date
    public let roots: [GroupNode]
    public let ledgersById: [Account.ID: LedgerNode]
    public let groupsById: [AccountGroup.ID: GroupNode]

    public init(companyId: Company.ID,
                groups: [AccountGroup],
                ledgers: [Account],
                ledgerBalances: [Account.ID: LedgerBalance]) {
        self.companyId = companyId
        self.builtAt = Date()

        var ledgerByGroup: [AccountGroup.ID: [LedgerNode]] = [:]
        var ledgersById: [Account.ID: LedgerNode] = [:]
        for ledger in ledgers {
            let bal = ledgerBalances[ledger.id] ?? LedgerBalance()
            let node = LedgerNode(
                id: ledger.id,
                groupId: ledger.groupId,
                code: ledger.code,
                name: ledger.name,
                openingBalancePaise: ledger.signedOpeningBalancePaise(),
                movementDebitPaise: bal.debitPaise,
                movementCreditPaise: bal.creditPaise,
                isActive: ledger.isActive,
                isBankAccount: ledger.isBankAccount,
                gstin: ledger.gstin
            )
            ledgersById[ledger.id] = node
            ledgerByGroup[ledger.groupId, default: []].append(node)
        }

        for (id, list) in ledgerByGroup {
            ledgerByGroup[id] = list.sorted { $0.code < $1.code }
        }

        var childrenGroups: [AccountGroup.ID: [AccountGroup]] = [:]
        for g in groups {
            if let parent = g.parentGroupId {
                childrenGroups[parent, default: []].append(g)
            }
        }
        for (id, list) in childrenGroups {
            childrenGroups[id] = list.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.code < $1.code) }
        }

        func buildGroup(_ group: AccountGroup) -> GroupNode {
            let childGroups = (childrenGroups[group.id] ?? []).map(buildGroup)
            let childLedgers = ledgerByGroup[group.id] ?? []
            return GroupNode(
                id: group.id,
                parentId: group.parentGroupId,
                code: group.code,
                name: group.name,
                nature: group.nature,
                sortOrder: group.sortOrder,
                childGroups: childGroups,
                childLedgers: childLedgers
            )
        }

        let roots = groups
            .filter { $0.parentGroupId == nil }
            .sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.code < $1.code) }
            .map(buildGroup)

        self.roots = roots
        self.ledgersById = ledgersById

        var groupsByIdResolved: [AccountGroup.ID: GroupNode] = [:]
        func register(_ node: GroupNode) {
            groupsByIdResolved[node.id] = node
            node.childGroups.forEach(register)
        }
        roots.forEach(register)
        self.groupsById = groupsByIdResolved
    }

    public func findGroup(_ id: AccountGroup.ID) -> GroupNode? { groupsById[id] }
    public func findLedger(_ id: Account.ID) -> LedgerNode? { ledgersById[id] }

    public func groupPath(of groupId: AccountGroup.ID) -> [GroupNode] {
        var out: [GroupNode] = []
        var current = groupsById[groupId]
        while let node = current {
            out.append(node)
            current = node.parentId.flatMap { groupsById[$0] }
        }
        return out.reversed()
    }

    public func groupPath(ofLedger ledgerId: Account.ID) -> [GroupNode] {
        guard let ledger = ledgersById[ledgerId] else { return [] }
        return groupPath(of: ledger.groupId)
    }

    public func breadcrumb(of ledgerId: Account.ID) -> String {
        let segments = groupPath(ofLedger: ledgerId).map { $0.name } + [ledgersById[ledgerId]?.name ?? ""]
        return segments.filter { !$0.isEmpty }.joined(separator: " › ")
    }

    public var allLedgers: [LedgerNode] {
        var out: [LedgerNode] = []
        func walk(_ node: GroupNode) {
            out.append(contentsOf: node.childLedgers)
            node.childGroups.forEach(walk)
        }
        roots.forEach(walk)
        return out
    }
}

public final class GroupNode: Identifiable, Hashable, @unchecked Sendable {
    public let id: AccountGroup.ID
    public let parentId: AccountGroup.ID?
    public let code: String
    public let name: String
    public let nature: AccountNature
    public let sortOrder: Int
    public let childGroups: [GroupNode]
    public let childLedgers: [LedgerNode]
    public let balancePaise: Int64

    public init(id: AccountGroup.ID,
                parentId: AccountGroup.ID?,
                code: String,
                name: String,
                nature: AccountNature,
                sortOrder: Int,
                childGroups: [GroupNode],
                childLedgers: [LedgerNode]) {
        self.id = id
        self.parentId = parentId
        self.code = code
        self.name = name
        self.nature = nature
        self.sortOrder = sortOrder
        self.childGroups = childGroups
        self.childLedgers = childLedgers
        self.balancePaise = (childGroups.map { $0.balancePaise }.reduce(0, +)) +
                            (childLedgers.map { $0.balancePaise }.reduce(0, +))
    }

    public static func == (lhs: GroupNode, rhs: GroupNode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public final class LedgerNode: Identifiable, Hashable, @unchecked Sendable {
    public let id: Account.ID
    public let groupId: AccountGroup.ID
    public let code: String
    public let name: String
    public let openingBalancePaise: Int64
    public let movementDebitPaise: Int64
    public let movementCreditPaise: Int64
    public let balancePaise: Int64
    public let isActive: Bool
    public let isBankAccount: Bool
    public let gstin: String?

    public init(id: Account.ID,
                groupId: AccountGroup.ID,
                code: String,
                name: String,
                openingBalancePaise: Int64,
                movementDebitPaise: Int64,
                movementCreditPaise: Int64,
                isActive: Bool,
                isBankAccount: Bool,
                gstin: String?) {
        self.id = id
        self.groupId = groupId
        self.code = code
        self.name = name
        self.openingBalancePaise = openingBalancePaise
        self.movementDebitPaise = movementDebitPaise
        self.movementCreditPaise = movementCreditPaise
        self.isActive = isActive
        self.isBankAccount = isBankAccount
        self.gstin = gstin
        self.balancePaise = openingBalancePaise + movementDebitPaise - movementCreditPaise
    }

    public static func == (lhs: LedgerNode, rhs: LedgerNode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct LedgerBalance: Sendable {
    public var debitPaise: Int64
    public var creditPaise: Int64

    public init(debitPaise: Int64 = 0, creditPaise: Int64 = 0) {
        self.debitPaise = debitPaise
        self.creditPaise = creditPaise
    }
}
