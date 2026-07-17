import Foundation

public enum TaxLedgerRole: Sendable, Hashable {
    case input
    case output
    case any
}

public enum AccountSelectionContext: Sendable, Hashable {
    case voucherParty(VoucherType.Code)
    case voucherPrimaryCashBank(VoucherType.Code)
    case voucherParticular(VoucherType.Code)
    case salesLedger
    case purchaseLedger
    case itemInvoiceParty(VoucherType.Code)
    case bankReconciliation
    case payrollExpense
    case payrollSettlement
    case orderParty(InventoryOrderType)
    case taxLedger(TaxLedgerRole)
    case stockAdjustment
    case costAllocation
    case unrestrictedPosting
}

public struct AccountEligibility: Sendable, Equatable {
    public let isEligible: Bool
    public let rejectionReason: String?
    public let ranking: Int

    public init(isEligible: Bool, rejectionReason: String? = nil, ranking: Int = 0) {
        self.isEligible = isEligible
        self.rejectionReason = rejectionReason
        self.ranking = ranking
    }
}

public protocol AccountEligibilityEvaluating: Sendable {
    func evaluate(
        account: Account,
        for context: AccountSelectionContext,
        company: Company,
        groups: [AccountGroup]
    ) -> AccountEligibility
}

/// The single semantic policy for account pickers and service validation.
/// Meaning comes from frozen group codes over the complete ancestor chain;
/// display names never affect accounting eligibility.
public struct AccountEligibilityPolicy: AccountEligibilityEvaluating {
    private let partyUsageByAccountId: [Account.ID: PartyUsage]

    public init(partyUsageByAccountId: [Account.ID: PartyUsage] = [:]) {
        self.partyUsageByAccountId = partyUsageByAccountId
    }

    public static func loading(db: SQLiteDatabase, companyId: Company.ID) throws -> AccountEligibilityPolicy {
        AccountEligibilityPolicy(
            partyUsageByAccountId: try PartyProfileRepository(db: db).usageByAccountId(companyId: companyId)
        )
    }

    public func evaluate(
        account: Account,
        for context: AccountSelectionContext,
        company: Company,
        groups: [AccountGroup]
    ) -> AccountEligibility {
        guard account.companyId == company.id else {
            return rejected("Account belongs to another company.")
        }
        guard account.isActive else {
            return rejected("Account is inactive.")
        }

        let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        guard let ancestry = ancestry(for: account, groupByID: groupByID) else {
            return rejected("Account group is missing or has an invalid hierarchy.")
        }
        guard ancestry.allSatisfy({ $0.companyId == company.id && $0.isActive }) else {
            return rejected("Account group is inactive or belongs to another company.")
        }

        let codes = Set(ancestry.map(\.code))
        // `CASH_IN_HAND` is a frozen built-in semantic code retained for
        // compatibility with early company databases where that ledger was
        // placed directly under Current Assets. Display names are never used.
        let isCashBank = account.isBankAccount
            || account.code == "CASH_IN_HAND"
            || !codes.isDisjoint(with: Self.cashBankRootCodes)
        let explicitPartyUsage = partyUsageByAccountId[account.id]
        let isCustomer = explicitPartyUsage?.permitsCustomerUse ?? codes.contains("SUNDRY_DEBTORS")
        let isSupplier = explicitPartyUsage?.permitsSupplierUse ?? codes.contains("SUNDRY_CREDITORS")
        let isSales = codes.contains("SALES_ACCOUNTS")
        let isPurchase = codes.contains("PURCHASE_ACCOUNTS")
        let isTax = codes.contains("DUTIES_TAXES")
        let isStock = codes.contains("STOCK_IN_HAND")
        let nature = ancestry.first?.nature

        switch context {
        case .unrestrictedPosting:
            return accepted()
        case .voucherPrimaryCashBank, .bankReconciliation:
            return isCashBank ? accepted(ranking: account.isBankAccount ? 30 : 20) : rejected("Select a cash, bank, or bank-overdraft ledger.")
        case .voucherParticular(let type):
            if type == .contra {
                return isCashBank ? accepted(ranking: 20) : rejected("Contra particulars must be cash or bank ledgers.")
            }
            if type == .payment || type == .receipt {
                return !isCashBank ? accepted() : rejected("Choose cash or bank in the voucher Account field.")
            }
            return accepted()
        case .salesLedger:
            return isSales ? accepted(ranking: 30) : rejected("Select a ledger under Sales Accounts.")
        case .purchaseLedger:
            return isPurchase ? accepted(ranking: 30) : rejected("Select a ledger under Purchase Accounts.")
        case .voucherParty(let type), .itemInvoiceParty(let type):
            return partyEligibility(
                type: type,
                isCustomer: isCustomer,
                isSupplier: isSupplier,
                hasExplicitProfile: explicitPartyUsage != nil
            )
        case .orderParty(let type):
            switch type {
            case .salesOrder:
                return isCustomer ? accepted(ranking: explicitPartyUsage == nil ? 30 : 40) : rejected("Select a customer party ledger.")
            case .purchaseOrder:
                return isSupplier ? accepted(ranking: explicitPartyUsage == nil ? 30 : 40) : rejected("Select a supplier party ledger.")
            }
        case .payrollExpense:
            return nature == .expense ? accepted(ranking: 20) : rejected("Select an expense ledger for payroll.")
        case .payrollSettlement:
            return (isCashBank || isSupplier) ? accepted(ranking: isCashBank ? 30 : 20) : rejected("Select a cash, bank, or payroll-payable ledger.")
        case .taxLedger(let role):
            guard isTax else { return rejected("Select a ledger under Duties & Taxes.") }
            switch role {
            case .any:
                return accepted(ranking: 20)
            case .input:
                return Self.inputTaxAccountCodes.contains(account.code)
                    ? accepted(ranking: 30)
                    : rejected("Select an input-tax ledger.")
            case .output:
                return Self.outputTaxAccountCodes.contains(account.code)
                    ? accepted(ranking: 30)
                    : rejected("Select an output-tax ledger.")
            }
        case .stockAdjustment:
            return isStock ? accepted(ranking: 20) : rejected("Select a ledger under Stock-in-Hand.")
        case .costAllocation:
            return (nature == .expense || nature == .income) ? accepted(ranking: 10) : rejected("Cost allocation requires an income or expense ledger.")
        }
    }

    private func partyEligibility(type: VoucherType.Code,
                                  isCustomer: Bool,
                                  isSupplier: Bool,
                                  hasExplicitProfile: Bool) -> AccountEligibility {
        let preferredRank = hasExplicitProfile ? 40 : 30
        switch type {
        case .sales, .receipt, .creditNote:
            return isCustomer ? accepted(ranking: preferredRank) : rejected("Select a customer party ledger.")
        case .purchase, .payment, .debitNote:
            return isSupplier ? accepted(ranking: preferredRank) : rejected("Select a supplier party ledger.")
        default:
            return (isCustomer || isSupplier) ? accepted(ranking: hasExplicitProfile ? 30 : 20) : rejected("Select a customer or supplier party ledger.")
        }
    }

    private func ancestry(
        for account: Account,
        groupByID: [AccountGroup.ID: AccountGroup]
    ) -> [AccountGroup]? {
        var result: [AccountGroup] = []
        var nextID: AccountGroup.ID? = account.groupId
        var visited: Set<AccountGroup.ID> = []
        while let id = nextID {
            guard visited.insert(id).inserted, let group = groupByID[id] else { return nil }
            result.append(group)
            nextID = group.parentGroupId
        }
        return result.isEmpty ? nil : result
    }

    private func accepted(ranking: Int = 0) -> AccountEligibility {
        AccountEligibility(isEligible: true, ranking: ranking)
    }

    private func rejected(_ reason: String) -> AccountEligibility {
        AccountEligibility(isEligible: false, rejectionReason: reason)
    }

    private static let cashBankRootCodes: Set<String> = ["CASH_IN_HAND", "BANK_ACCOUNTS", "BANK_OD"]
    private static let inputTaxAccountCodes: Set<String> = ["CGST_INPUT", "SGST_INPUT", "IGST_INPUT", "CESS_INPUT"]
    private static let outputTaxAccountCodes: Set<String> = ["CGST_OUTPUT", "SGST_OUTPUT", "IGST_OUTPUT", "CESS_OUTPUT"]
}
