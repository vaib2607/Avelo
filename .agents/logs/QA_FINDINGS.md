# QA Findings — I Section

## Company Setup
- Status: clean
- Verified company creation seeds a new company file, inserts the company and FY, and records audit events for both actions.
- Verified `openCompany(...)` loads the most recent FY into the active context and reloads the account tree.
- Verified focused tests passed: `AppEnvironmentFlowTests` `testOpenCompanyAfterCreateSetsUsableContext`, `testEnvironmentCanOpenRestoredCompanyIntoUsableContext`, `testOpeningSecondCompanyResetsRouterAndSwapsVisibleContext`.
- Blocker: none found.

## Accounts
- Status: clean
- Verified account creation validates required fields, group selection, uniqueness, and GSTIN format before save.
- Verified created/edited/disabled accounts are persisted through `AccountService` and each action records an audit event.
- Verified inactive accounts are excluded from active account pickers via `listActiveAccounts()`, while the full accounts list still supports `showDisabled`.
- Verified focused tests passed: `AccountTreeReconciliationTests` and `CompanyIsolationTests`.
- Blocker: none found.

## Voucher Posting, Edit, Reversal
- Status: clean
- Verified posting rejects unbalanced drafts with a clear validation error and persists balanced vouchers with equal debit/credit totals.
- Verified edits in locked FY reject with `voucherFYLocked`.
- Verified reversals create a linked reversal voucher, preserve the original voucher, and net account movements back to zero.
- Verified rollback safety when account-usage updates fail during post/edit/reverse.
- Verified audit coverage for voucher post/edit/reverse.
- Verified focused tests passed: `VoucherServiceTests`, `AuditCoverageTests`, `ValidationFailureModeTests`.
- Blocker: none found.

## FY Lock Behavior
- Status: clean
- Verified FY locking is persisted and audited through `FinancialYearService.lock`.
- Verified backdated voucher posting into a locked FY is rejected with `voucherFYLocked`.
- Verified editing an existing voucher in a locked FY is rejected with `voucherFYLocked`.
- Verified focused tests passed: `FinancialYearServiceTests`, `VoucherServiceTests.testPostInLockedFinancialYearThrows`, `VoucherServiceTests.testEditInLockedFinancialYearThrows`.
- Blocker: none found.

## Reports
- Status: clean
- Verified trial balance, P&L, balance sheet, GST summary, day book, ledger, and outstanding reports respect date boundaries and carry source voucher linkage for drill-down.
- Verified seeded reconciliation tests match fixture expectations and SQL-derived authoritative totals for trial balance, P&L, and balance sheet.
- Verified focused tests passed: `ReportBehaviorTests`, `BalanceSheetReconciliationTests`, `ProfitLossReconciliationTests`.
- Blocker: none found.

## Backup/Restore
- Status: clean
- Verified restore remaps company identity, restores FY/account data, and writes a backup-import audit event.
- Verified backup/restore round-trip preserves posted vouchers and company metadata.
- Verified repeated restore/reopen cycles remain stable and preserve report balance-sheet invariants.
- Verified focused tests passed: `RestoreServiceTests`, `AuditCoverageTests`.
- Blocker: none found.

## Voucher Posting, Edit, Reversal
- Status: clean
- Verified balanced voucher posting persists debit and credit lines with equal totals and rejects unbalanced drafts.
- Verified edit and reversal paths roll back cleanly if account-usage updates fail, and reversal preserves zero net movement.
- Verified locked FY prevents post and edit actions in shipped paths.
- Verified focused tests passed: `VoucherServiceTests`, `VoucherDraftTests`, `AuditCoverageTests`.
- Blocker: none found.

## FY Lock
- Status: clean
- Verified locked FY rejects new voucher posts and edits in shipped write paths.
- Verified the lock action records an audit event.
- Verified focused tests passed: `FinancialYearServiceTests`, `VoucherServiceTests`.
- Blocker: none found.

## Reports
- Status: clean
- Verified trial balance, P&L, and balance sheet reconciliation tests match seeded and live SQL totals.
- Verified ledger, day book, GST summary, and outstanding reports respect date boundaries and source voucher linkage.
- Verified focused tests passed: `AccountTreeReconciliationTests`, `ProfitLossReconciliationTests`, `BalanceSheetReconciliationTests`, `ReportBehaviorTests`.
- Blocker: none found.

## Backup/Restore
- Status: clean
- Verified backup export uses the registered SQLite filename and fails clearly when the destination path is missing.
- Verified restore round-trip preserves company data and writes audit events.
- Verified focused tests passed: `DatabaseManagerFileResolutionTests`, `RestoreServiceTests`.
- Blocker: none found.

## Release Gates
- Status: clean
- Zero known P0 bugs in shipped scope: confirmed by release board and passing shipped-path tests.
- Zero silent data-loss or deletion paths: confirmed by restore and voucher delete regression coverage.
- Zero FY lock bypasses: confirmed by locked-year voucher tests and FY lock coverage.
- Zero network behavior: confirmed by `make net-check` returning zero matches.
- Core reports reconcile on validation data: confirmed by report reconciliation tests.
