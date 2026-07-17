# Avelo Accounting Logic Audit

Date: 2026-07-17  
Scope: current worktree, read-only accounting correctness review  
Status: audited findings implemented; broader release acceptance remains open

## Executive result

The posting pipeline generally enforces balanced positive lines, company ownership, FY resolution, and a shared account-eligibility policy. The overall accounting/reporting logic is not yet reliable for release because several reports either classify accounts with different rules from voucher entry or expose incomplete/wrong amounts while still reconciling at a headline total.

The current worktree also has an unrelated test-compilation blocker in `Tests/AveloTests/SchemaDriftTests.swift:490`: `XCTAssertEqual(try db.userVersion(), Int64(SchemaVersion.current.rawValue))` is ambiguous. The focused accounting tests therefore could not execute on this worktree.

## Account-semantics matrix

This is the audit contract used to compare account selection, posting, and reports. “Explicit ledger mode” means the user supplies the Dr/Cr lines; the service must still validate account ownership, activity, and group eligibility where the workflow has a semantic field.

| Account class | Normal balance | Increase / valid side | Decrease / valid side | Workflow use | Report destination |
|---|---|---|---|---|---|
| Cash and bank assets | Dr | Debit | Credit | Payment account is Cr; receipt account is Dr; contra destination is Dr | Balance sheet assets; cash flow |
| Bank overdraft | Cr | Credit | Debit | Cash/bank-class account; contra and payment/receipt behavior must preserve the actual signed balance | Balance sheet liabilities; financing cash flow |
| Trade receivables / customer party | Dr | Debit | Credit | Sales/receipt/credit-note party roles; explicit dual-role profile may widen use | Balance sheet assets; outstanding receivables |
| Trade payables / supplier party | Cr | Credit | Debit | Purchase/payment/debit-note party roles; explicit dual-role profile may widen use | Balance sheet liabilities; outstanding payables |
| Sales and other income | Cr | Credit | Debit | Sales ledger or explicit journal line | P&L income |
| Purchases and expenses | Dr | Debit | Credit | Purchase ledger, payroll expense, or explicit journal line | P&L expense |
| Input tax | Dr | Debit | Credit | Purchase/item invoice tax line | GST input and balance-sheet tax asset/debit presentation |
| Output tax | Cr | Credit | Debit | Sales/item invoice tax line | GST output and balance-sheet tax liability |
| Stock-in-hand | Dr | Debit | Credit | Item-invoice/inventory effects; manual stock policy applies | Balance sheet assets; stock reports |
| Capital, reserves, loans, provisions | Cr | Credit | Debit | Explicit ledger/opening entries and workflow-specific settlement | Balance sheet liabilities/equity |
| Suspense, branch/division, miscellaneous assets | Nature-dependent; seeded nature is authoritative | Explicit ledger/opening entry | Explicit ledger/opening entry | Unrestricted ledger mode only unless a specific workflow grants a role | Balance sheet or reconciliation section according to group nature |

### Workflow Dr/Cr expectations

| Voucher/workflow | Expected automatic shape |
|---|---|
| Payment | Cash/bank credit; non-cash/bank particular debit |
| Receipt | Cash/bank debit; non-cash/bank particular credit |
| Contra | Cash/bank destination debit; cash/bank source credit; no ordinary ledger |
| Sales item invoice | Customer/cash debit; sales ledger credit; output tax credit; round-off may be either side |
| Purchase item invoice | Supplier/cash credit; purchase ledger debit; input tax debit; round-off may be either side |
| Journal | Explicit balanced lines; no semantic inference from account display names |
| Credit/debit note in ledger mode | Explicit balanced corrective lines, with party eligibility matching the voucher family; automatic item-invoice behavior is not assumed unless separately implemented |
| Payroll | Expense debit; payroll payable or eligible settlement account credit; net salary must reconcile |
| Opening/FY carry-forward | Signed opening balance is preserved; the displayed Dr/Cr side follows the resulting signed balance |

## Findings

### P1 — P&L account rows contained zero amounts — fixed

**Evidence:** `Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift:72-100` computes each income/expense account's net amount into `absNet`, but constructs every `TrialBalanceRow` with `debitPaise: 0, creditPaise: 0`. `Avelo/Features/Reports/ReportsBody+FinancialStatements.swift:90-118` renders those fields as the account amount.

**Reproduction:** Post ₹500 income and ₹200 expense, then open P&L. Section totals are ₹500 and ₹200, but the account rows display ₹0. Comparative rows are also unusable because the current-year row has no account amount.

**Expected:** Each income row exposes its signed/normal-balance amount and each expense row exposes its signed/normal-balance amount. Section totals equal the sum of displayed rows.

**Impact:** Users cannot identify which ledger produced P&L totals and drill-down values disagree with the report headline. Required regression: assert both account row values and section totals.

**Implementation:** `ReportRepository+FinancialStatements` now emits normal-balance Dr/Cr row amounts, and the reports view renders income as Cr less Dr and expenses as Dr less Cr. Regression coverage is in `ReportBehaviorTests.testProfitLossRowsCarryTheAmountsShownByTheirSectionTotals`.

### P1 — Balance sheet omitted valid seeded account groups — fixed

**Evidence:** `Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift:125-128` only searches assets under `FIXED_ASSETS`, `INVESTMENTS`, `CURRENT_ASSETS`, `STOCK_IN_HAND`, `BANK_ACCOUNTS`, and liabilities under `CAPITAL`, `LOANS`, `CURRENT_LIAB`, `DUTIES_TAXES`.

The seeded chart also contains `MISC_EXPENSES_ASSET`, `SUSPENSE`, `BRANCH_DIVISIONS`, and `RESERVES_SURPLUS` in `Avelo/Resources/Seed/DefaultChartOfAccounts.json:7-18`.

**Reproduction:** Create a ledger under any omitted group, post a non-zero balance, and run the balance sheet. The ledger is absent; the difference is absorbed into `balancingEquityPaise`.

**Expected:** Every active account group with asset or liability nature appears exactly once in the balance sheet, including custom descendants of those groups.

**Impact:** Material balances can disappear from the balance sheet while the report still appears internally balanced.

**Implementation:** Balance-sheet sections now include every active group matching the account nature, including custom descendants and previously omitted seeded groups. Regression coverage is in `BalanceSheetReconciliationTests.testBalanceSheetIncludesAssetGroupsOutsideTheDefaultCurrentAssetRoots`.

### P1 — GST summary exposed tax buckets as taxable-base properties — fixed

**Evidence:** `Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift:8-15` creates output/input buckets only for tax ledgers. `Avelo/Core/Models/ReportResult.swift:230-233` defines `outputTaxablePaise` as `output.first`, `outputTaxPaise` as `output.dropFirst().first`, and equivalent input properties.

**Reproduction:** Post a sales invoice with CGST and SGST. `outputTaxablePaise` returns CGST output tax, while `outputTaxPaise` returns SGST output tax. No taxable-base bucket exists in this report query.

**Expected:** Taxable value comes from posted invoice/item rows or an explicitly defined taxable-base aggregation; tax properties independently sum the appropriate tax ledgers.

**Impact:** GST UI and exported summary values are mislabeled and unsuitable for statutory review. Required regression: assert taxable base, CGST, SGST, IGST, CESS, input, output, and net payable separately.

**Implementation:** `GstSummary` now stores distinct output/input taxable bases and checked output/input tax totals. Taxable bases come from posted item-invoice rows; CESS is classified by voucher family. Regression assertions were added to `ReportBehaviorTests`.

### P1 — Report implementations did not consistently honor report filters — substantially fixed

**Evidence:**

- `ReportRepository.movementTotals` in `Avelo/Core/Repositories/ReportRepository.swift:21-57` filters company and dates but not `v.company_id`, `v.financial_year_id`, `v.is_posted`, or voucher status.
- `dayBook` in `Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift:53-76` ignores `financialYearId`, `voucherTypeCodes`, and cancellation/posted policy.
- `outstandingEvents` in `Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift:111-164` filters company and date but not posted/status/FY policy.
- `cashFlow` in `Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift:233-314` filters company/date but not `financialYearId` or account semantic identity.
- `gstSummary` uses `movementTotals`, so it inherits the same filter limitations.

**Expected:** Every report applies every filter that changes its meaning and has one documented policy for cancelled/reversed vouchers.

**Impact:** A report can show a different period/FY/company population from the ledger screen or from another report. Required regression: create adjacent FYs, cancelled/reversed vouchers, and filter-specific voucher types, then compare each report to authoritative SQL.

**Implementation:** Shared movement aggregation, ledger, day book, outstanding, GST, and cash-flow queries now enforce company ownership, posted state, FY, dates, and applicable voucher-type filters. Cancellation remains included as preserved history paired with its linked reversal; that policy still requires explicit accountant acceptance.

### P1 — Cash-flow account detection bypassed account semantics — fixed

**Evidence:** `Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift:244-260` identifies cash/bank accounts using `UPPER(a.code) LIKE '%CASH%' OR ... LIKE '%BANK%'`. The canonical policy in `Avelo/Core/Validation/AccountEligibilityPolicy.swift:84-104` uses bank metadata and frozen group ancestry.

**Reproduction:** Create a valid bank ledger with code `HDFC001` and `isBankAccount = true`; it is not treated as cash/bank by cash flow. Create a non-bank liability ledger with `BANK` in its code; it is treated as cash/bank.

**Expected:** Cash-flow classification uses the same account semantic policy as voucher entry and bank reconciliation.

**Impact:** Cash flow can omit real bank movement or classify ordinary liabilities as cash accounts.

**Implementation:** Cash-flow cash/bank detection now uses `AccountEligibilityPolicy` with the same ancestry and bank metadata as voucher entry and bank reconciliation.

### P2 — Stock ageing did not constrain movements by company — fixed

**Evidence:** `Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift:272-274` filters stock movements by item IDs and date but not `company_id`, unlike the company-scoped item lookup.

**Expected:** Stock reports must enforce item and movement company ownership in SQL.

**Impact:** UUID collisions or malformed cross-company rows can leak stock quantities/value into a company report. Required regression: insert a foreign-company movement for a same-ID fixture and assert isolation/fail-closed behavior.

**Implementation:** Stock-ageing aggregation now requires the active company ID in SQL. A dedicated foreign-company collision regression remains recommended.

### P2 — UI silently converted checked arithmetic failures to zero — fixed

**Evidence:** `Avelo/Features/Reports/ReportsBody+FinancialStatements.swift:5-10` and multiple render sites use `try? ... ?? 0` for report amounts.

**Expected:** A checked arithmetic failure remains visible as a typed report/UI error; it must not be presented as a zero financial amount.

**Impact:** Overflow or malformed derived data can appear as a valid zero in the UI, violating the fail-closed accounting rule.

**Implementation:** Financial report rendering now displays `Calculation error` when checked arithmetic fails, and trial-balance totals show an explicit error state instead of substituting zero.

## Confirmed strengths

- `AccountEligibilityPolicy` resolves meaning from company ownership, active state, complete group ancestry, frozen semantic codes, and explicit party profiles. It does not infer account roles from display names.
- `VoucherDraftValidator` enforces minimum lines, positive amounts, balance, FY resolution, FY lock, account ownership/activity, and party eligibility.
- Payment, receipt, and contra single-entry shapes are checked in `VoucherDraftValidator.singleEntryVoucherErrors`.
- Reversal/cancellation creates linked opposite ledger effects and preserves the original record and audit lineage.
- `AccountNature.normalBalance` correctly maps assets/expenses to debit and liabilities/income to credit.
- `make rule-audit` passed the offline, placeholder, observation, and money-path checks on this worktree.

## Regression scenario catalogue

The following scenarios must become executable tests before accounting fixes are considered complete:

1. Run every voucher family through its valid and invalid account matrix, including payment, receipt, contra, sales, purchase, credit note, debit note, journal, payroll, and opening.
2. Assert normal-balance and cross-over behavior for assets, liabilities, income, expenses, overdrafts, parties, taxes, stock, suspense, reserves, branch/division, and miscellaneous assets.
3. Assert customer/supplier dual-role profiles and rejection of inactive, foreign, missing, cyclic, and group-as-ledger references.
4. Assert item-invoice tax lines, taxable bases, CESS, round-off, stock effects, reversal, cancellation, and report lineage.
5. Assert adjacent-FY opening carry-forward, locked-period correction, reversal date, and report filtering.
6. Assert P&L account rows equal displayed section totals, balance-sheet group completeness, and trial-balance Dr/Cr reconciliation.
7. Assert GST, outstanding, banking, cash-flow, stock valuation, and stock ageing use the same company/FY/status/date population.
8. Assert cancellation/reversal treatment is explicit and consistent across ledger, day book, trial balance, P&L, balance sheet, GST, outstanding, and cash flow.

## Validation status

- `make rule-audit`: passed.
- Focused Swift tests: passed after resolving the existing `SchemaDriftTests.swift:490` type-ambiguity blocker.
- Full test suite: compiled and ran 523 tests; 5 failures remain in pre-existing backup-path expectations (`DatabaseManagerFileResolutionTests` and `RestoreServiceTests`), outside this accounting change.
- GUI, accountant, operator, keyboard, accessibility, visual, printing, and release acceptance: not performed by this audit.

## Recommended fix order

1. Completed: resolve the test compilation blocker and restore focused proof.
2. Completed: fix P&L row amounts, balance-sheet group traversal, GST taxable/tax separation, report filters, cash-flow semantics, stock ownership, and visible arithmetic failures.
3. Remaining: define and obtain accountant acceptance for cancellation/reversal report treatment.
4. Remaining: add the broader adjacent-FY, foreign-company collision, voucher-type, and item-invoice regression scenarios listed above.
5. Remaining: resolve the unrelated backup-path test failures before claiming a clean full-suite release gate.
