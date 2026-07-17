import XCTest
@testable import Avelo

final class AccountEligibilityPolicyTests: XCTestCase {
    private let policy = AccountEligibilityPolicy()

    func testResolvesCashBankAndSalesMeaningThroughCompleteAncestry() {
        let company = Company(name: "Eligibility Co")
        let bankRoot = group(company, code: "BANK_ACCOUNTS", nature: .assets)
        let bankChild = group(company, code: "CURRENT_BANKS", nature: .assets, parent: bankRoot.id)
        let salesRoot = group(company, code: "SALES_ACCOUNTS", nature: .income)
        let salesChild = group(company, code: "DOMESTIC_SALES", nature: .income, parent: salesRoot.id)
        let groups = [bankRoot, bankChild, salesRoot, salesChild]

        XCTAssertTrue(policy.evaluate(account: account(company, group: bankChild), for: .bankReconciliation, company: company, groups: groups).isEligible)
        XCTAssertTrue(policy.evaluate(account: account(company, group: salesChild), for: .salesLedger, company: company, groups: groups).isEligible)
    }

    func testNeverInfersCashOrBankFromDisplayName() {
        let company = Company(name: "Eligibility Co")
        let expense = group(company, code: "INDIRECT_EXPENSES", nature: .expense)
        let misleading = account(company, group: expense, code: "OFFICE", name: "Cash Bank Sales Purchase")

        let result = policy.evaluate(account: misleading, for: .bankReconciliation, company: company, groups: [expense])

        XCTAssertFalse(result.isEligible)
        XCTAssertNotNil(result.rejectionReason)
    }

    func testRejectsInactiveForeignMissingAndCyclicHierarchy() {
        let company = Company(name: "Eligibility Co")
        let foreign = Company(name: "Foreign Co")
        let root = group(company, code: "CASH_IN_HAND", nature: .assets)
        var inactive = account(company, group: root)
        inactive.isActive = false
        XCTAssertFalse(policy.evaluate(account: inactive, for: .bankReconciliation, company: company, groups: [root]).isEligible)
        XCTAssertFalse(policy.evaluate(account: account(foreign, group: group(foreign, code: "CASH_IN_HAND", nature: .assets)), for: .bankReconciliation, company: company, groups: [root]).isEligible)

        let missing = account(company, group: group(company, code: "MISSING", nature: .assets))
        XCTAssertFalse(policy.evaluate(account: missing, for: .unrestrictedPosting, company: company, groups: [root]).isEligible)

        var first = group(company, code: "A", nature: .assets)
        let second = group(company, code: "B", nature: .assets, parent: first.id)
        first.parentGroupId = second.id
        let cyclicAccount = account(company, group: first)
        XCTAssertFalse(policy.evaluate(account: cyclicAccount, for: .unrestrictedPosting, company: company, groups: [first, second]).isEligible)
    }

    func testVoucherContextsSeparatePrimaryParticularPartyAndTradeLedgers() {
        let company = Company(name: "Eligibility Co")
        let cash = group(company, code: "CASH_IN_HAND", nature: .assets)
        let debtors = group(company, code: "SUNDRY_DEBTORS", nature: .assets)
        let creditors = group(company, code: "SUNDRY_CREDITORS", nature: .liabilities)
        let sales = group(company, code: "SALES_ACCOUNTS", nature: .income)
        let purchase = group(company, code: "PURCHASE_ACCOUNTS", nature: .expense)
        let groups = [cash, debtors, creditors, sales, purchase]

        XCTAssertTrue(policy.evaluate(account: account(company, group: cash), for: .voucherPrimaryCashBank(.payment), company: company, groups: groups).isEligible)
        XCTAssertFalse(policy.evaluate(account: account(company, group: cash), for: .voucherParticular(.payment), company: company, groups: groups).isEligible)
        XCTAssertTrue(policy.evaluate(account: account(company, group: debtors), for: .voucherParty(.sales), company: company, groups: groups).isEligible)
        XCTAssertFalse(policy.evaluate(account: account(company, group: creditors), for: .voucherParty(.sales), company: company, groups: groups).isEligible)
        XCTAssertTrue(policy.evaluate(account: account(company, group: sales), for: .salesLedger, company: company, groups: groups).isEligible)
        XCTAssertTrue(policy.evaluate(account: account(company, group: purchase), for: .purchaseLedger, company: company, groups: groups).isEligible)
    }

    func testExplicitDualRoleProfileAllowsBothCustomerAndSupplierWorkflows() {
        let company = Company(name: "Eligibility Co")
        let debtors = group(company, code: "SUNDRY_DEBTORS", nature: .assets)
        let party = account(company, group: debtors)
        let profiled = AccountEligibilityPolicy(partyUsageByAccountId: [party.id: .both])

        let sales = profiled.evaluate(account: party, for: .voucherParty(.sales), company: company, groups: [debtors])
        let purchase = profiled.evaluate(account: party, for: .voucherParty(.purchase), company: company, groups: [debtors])

        XCTAssertTrue(sales.isEligible)
        XCTAssertTrue(purchase.isEligible)
        XCTAssertEqual(sales.ranking, 40)
        XCTAssertEqual(purchase.ranking, 40)
    }

    func testExplicitPartyUsageOverridesGroupAncestry() {
        let company = Company(name: "Eligibility Co")
        let creditors = group(company, code: "SUNDRY_CREDITORS", nature: .liabilities)
        let party = account(company, group: creditors)
        let profiled = AccountEligibilityPolicy(partyUsageByAccountId: [party.id: .customer])

        XCTAssertTrue(profiled.evaluate(account: party, for: .orderParty(.salesOrder), company: company, groups: [creditors]).isEligible)
        XCTAssertFalse(profiled.evaluate(account: party, for: .orderParty(.purchaseOrder), company: company, groups: [creditors]).isEligible)
    }

    func testTaxRoleRequiresExplicitFrozenInputOrOutputCode() {
        let company = Company(name: "Eligibility Co")
        let taxes = group(company, code: "DUTIES_TAXES", nature: .liabilities)
        let input = account(company, group: taxes, code: "CGST_INPUT")
        let output = account(company, group: taxes, code: "CGST_OUTPUT")

        XCTAssertTrue(policy.evaluate(account: input, for: .taxLedger(.input), company: company, groups: [taxes]).isEligible)
        XCTAssertFalse(policy.evaluate(account: input, for: .taxLedger(.output), company: company, groups: [taxes]).isEligible)
        XCTAssertTrue(policy.evaluate(account: output, for: .taxLedger(.output), company: company, groups: [taxes]).isEligible)
        XCTAssertFalse(policy.evaluate(account: output, for: .taxLedger(.input), company: company, groups: [taxes]).isEligible)
    }

    func testEveryCoreVoucherTypeUsesTheSameFieldContextMatrix() {
        let company = Company(name: "Eligibility Matrix")
        let cashGroup = group(company, code: "CASH_IN_HAND", nature: .assets)
        let debtors = group(company, code: "SUNDRY_DEBTORS", nature: .assets)
        let creditors = group(company, code: "SUNDRY_CREDITORS", nature: .liabilities)
        let expense = group(company, code: "INDIRECT_EXPENSES", nature: .expense)
        let groups = [cashGroup, debtors, creditors, expense]
        let cash = account(company, group: cashGroup, code: "CASH_IN_HAND")
        let customer = account(company, group: debtors, code: "CUSTOMER")
        let supplier = account(company, group: creditors, code: "SUPPLIER")
        let ordinary = account(company, group: expense, code: "EXPENSE")

        for type in VoucherType.Code.allCases {
            XCTAssertTrue(policy.evaluate(account: cash, for: .voucherPrimaryCashBank(type), company: company, groups: groups).isEligible, "\(type) primary cash/bank")
            XCTAssertFalse(policy.evaluate(account: ordinary, for: .voucherPrimaryCashBank(type), company: company, groups: groups).isEligible, "\(type) rejects ordinary primary")

            let cashParticular = policy.evaluate(account: cash, for: .voucherParticular(type), company: company, groups: groups).isEligible
            let ordinaryParticular = policy.evaluate(account: ordinary, for: .voucherParticular(type), company: company, groups: groups).isEligible
            if type == .contra {
                XCTAssertTrue(cashParticular)
                XCTAssertFalse(ordinaryParticular)
            } else if type == .payment || type == .receipt {
                XCTAssertFalse(cashParticular)
                XCTAssertTrue(ordinaryParticular)
            } else {
                XCTAssertTrue(cashParticular)
                XCTAssertTrue(ordinaryParticular)
            }

            let customerEligible = policy.evaluate(account: customer, for: .voucherParty(type), company: company, groups: groups).isEligible
            let supplierEligible = policy.evaluate(account: supplier, for: .voucherParty(type), company: company, groups: groups).isEligible
            switch type {
            case .sales, .receipt, .creditNote:
                XCTAssertTrue(customerEligible)
                XCTAssertFalse(supplierEligible)
            case .purchase, .payment, .debitNote:
                XCTAssertFalse(customerEligible)
                XCTAssertTrue(supplierEligible)
            default:
                XCTAssertTrue(customerEligible)
                XCTAssertTrue(supplierEligible)
            }
        }
    }

    private func group(_ company: Company, code: String, nature: AccountNature, parent: AccountGroup.ID? = nil) -> AccountGroup {
        AccountGroup(companyId: company.id, parentGroupId: parent, code: code, name: code, nature: nature)
    }

    private func account(_ company: Company, group: AccountGroup, code: String = "LEDGER", name: String = "Ledger") -> Account {
        Account(companyId: company.id, groupId: group.id, code: code, name: name)
    }
}
