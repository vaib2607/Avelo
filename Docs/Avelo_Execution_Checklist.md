# AVELO Master Execution Checklist

## Summary
This is the final master list for this thread. It is the only list we use going forward. We will strike items only when the item itself is complete, its proof-of-done check passes, and any dependency re-check required by that item also passes.

Execution rule:
- Work only from `Active Now`.
- When an item is done, strike it.
- When a dependency changes, re-check dependent completed items before moving forward.
- If scope changes, edit this list only. No side scope.
- Apply the release split in `Docs/Avelo_Release_Board.md`: `V1` for day-one correctness/open-save reliability, `V2` for post-launch merge/security/scale work, `V3` for later hardening and rare-edge-case resilience.

Status keys:
- `Owner`: `Code`, `Review`, `Test`, `Manual QA`, `Decision`
- `Depends`: prerequisite items that must be green first
- `Proof`: what must be true before striking the item

## RC Queue

- ~~Prove promoted shell routes for inventory, payroll, and banking behave as shipped features~~  
  Owner: `Test`  
  Depends: bundled app launch validation complete  
  Proof: sidebar, menu, keyboard, and command-palette navigation all resolve to the intended screens

- ~~Add a reproducible local `.app` bundle path~~  
  Owner: `Code`  
  Depends: release build green  
  Proof: `make bundle` produces `dist/Avelo.app`

- ~~Validate the bundled app launches cleanly for local RC~~  
  Owner: `Test`  
  Depends: local `.app` bundle path exists  
  Proof: the built app launches without an immediate startup crash

- ~~Re-run accountant-style QA on the built RC artifact~~  
  Owner: `Manual QA`  
  Depends: promoted shell routes validated  
  Proof: no shipped-path blocker found in the built artifact

- ~~Run RC stress, soak, and deployment validation~~  
  Owner: `Test`  
  Depends: built-artifact QA complete  
  Proof: no crash, corruption, or packaging blocker remains in local RC scope

## Worker Lane Status

- `ARCH`  
  What it is supposed to do: verify current release-path structure, module boundaries, deferred gating, and shipped-shell integrity for the built RC path.  
  Proof of done: structural report tied to current bundle/script surface and hidden/deferred entry-point state.  
  Current blocker: none proven; built RC path validated with bundle, self-test, launch smoke, and shipped-shell routing evidence.  
  Current task: verify the built RC path remains structurally sound after the last RC queue items are struck through.

- `FLOW`  
  What it is supposed to do: verify end-to-end shipped journeys on the built RC artifact.  
  Proof of done: built-artifact flow matrix for company setup, company switching, accounts, vouchers, FY lock, reports, backup, and restore.  
  Current blocker: proof-only gap; the packaging path exists, but `RB-042` is still open because the built-artifact pass is not fully recorded.  
  Current task: re-run accountant-style QA on `dist/Avelo.app`, using self-test coverage as baseline and manually confirming any journey not already proven.

- `QA`  
  What it is supposed to do: validate the shipped app surface as an accountant-style RC pass on the built artifact.  
  Proof of done: manual proof for launch, promoted shell routes, and accountant-critical bundled-app flows.  
  Current blocker: none proven; built-artifact QA now has direct RC-flow and bundle/self-test evidence.  
  Current task: hand off to RC stress, soak, and deployment validation completion.

- `TEST`  
  What it is supposed to do: classify automated RC evidence into already proven, re-run required, and still missing.  
  Proof of done: a green automated suite or a minimal failing set, plus an explicit RC evidence map for stress/soak/failure handling.  
  Current blocker: none proven; automated RC evidence now covers bundle validation, self-test, stress, and smoke.
  Current task: keep the RC evidence map in sync with the built artifact and release board.

- `DEPLOY`  
  What it is supposed to do: prove release build, bundle, launch, and local packaging readiness from current repo evidence.  
  Proof of done: release build, bundle validation, launch smoke, and self-test evidence reconciled against the current built artifact.  
  Current blocker: none proven; `swift build -c release`, `dist/Avelo.app`, `Scripts/validate_bundle.sh`, `Scripts/launch_smoke.sh`, and `Scripts/bundle_selftest.sh` now reconcile against the RC queue.  
  Current task: hand off to final ARCH go/no-go after the last RC queue items are struck through.

## Active Now

### A. Release Control
- ~~Create repo-tracked `P0/P1/P2` execution board~~  
  Owner: `Decision`  
  Depends: none  
  Proof: every known issue is listed once with a severity

- ~~Record top 10 blockers in execution order~~  
  Owner: `Decision`  
  Depends: execution board exists  
  Proof: top 10 blockers are numbered in order and map to checklist areas

- ~~Mark deferred modules and hidden entry points explicitly~~  
  Owner: `Review`  
  Depends: execution board exists  
  Proof: inventory, payroll, banking, advanced GST are marked `ship`, `defer`, or `conditional`

### B. Observation / Shell Completion
- ~~Migrate `AppEnvironment`, `AppRouter`, and `WindowState` to `@Observable`~~  
  Owner: `Code`  
  Proof: build green and no regression in app root flow

- ~~Move app composition root from `environmentObject` to typed environment injection~~  
  Owner: `Code`  
  Proof: root injection works and build green

- ~~Migrate shell views to typed environment access~~  
  Owner: `Code`  
  Proof: sidebar, company picker, banners, routing still work

- ~~Migrate `KeyboardBridge` and `KeyboardRouter`~~  
  Owner: `Code`  
  Proof: keyboard flow still works in shipped shell

- ~~Migrate `AccountTreeCache`~~  
  Owner: `Code`  
  Proof: cache-backed flows still load correctly

- ~~Remove `EnvironmentObject` usage from shipped shell and main feature entry screens~~  
  Owner: `Code`  
  Proof: no shipped core screen requires `@EnvironmentObject`

- ~~Migrate `OnboardingViewModel`~~  
  Owner: `Code`  
  Proof: onboarding flow still works end to end

- ~~Migrate `DashboardViewModel`~~  
  Owner: `Code`  
  Proof: dashboard loads and values are sane

- ~~Migrate `AccountsViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: accounts screen loads, filters work, build green, tests green

- ~~Remove `AccountsViewModelHolder`~~  
  Owner: `Code`  
  Depends: `AccountsViewModel` migrated  
  Proof: accounts screen no longer relies on holder wrapper

- ~~Migrate `ReportsViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: reports screen loads, selection/date changes work, build green, tests green

- ~~Remove `ReportsViewModelHolder`~~  
  Owner: `Code`  
  Depends: `ReportsViewModel` migrated  
  Proof: reports screen no longer relies on holder wrapper

- ~~Migrate `VouchersViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: voucher list loads, filters work, build green, tests green

- ~~Remove `VouchersViewModelHolder`~~  
  Owner: `Code`  
  Depends: `VouchersViewModel` migrated  
  Proof: vouchers list no longer relies on holder wrapper

- ~~Migrate `VoucherEditViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: voucher edit sheet loads, line edits work, validation still updates correctly

- ~~Remove `VoucherEditHolder`~~  
  Owner: `Code`  
  Depends: `VoucherEditViewModel` migrated  
  Proof: voucher sheet no longer relies on holder wrapper

- ~~Migrate `SettingsViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: settings/FY screen loads and actions still work

- ~~Migrate `AuditViewModel`~~  
  Owner: `Code`  
  Depends: shell migration base complete  
  Proof: audit screen loads, filters still work

- ~~Remove `AuditViewModelHolder`~~  
  Owner: `Code`  
  Depends: `AuditViewModel` migrated  
  Proof: audit screen no longer relies on holder wrapper

- ~~Confirm no shipped workflow mixes old and new observation systems~~  
  Owner: `Review`  
  Depends: all shipped release-path migrations above complete  
  Proof: no release-path `ObservableObject`, `@Published`, or `@EnvironmentObject` remains in shipped core path

## Unlocked Next

### C. Schema Source Of Truth
- ~~Remove silent-delete schema violation on `avelo_ledger_lines.voucher_id`~~  
  Owner: `Code`  
  Proof: delete path no longer cascades silently

- ~~Reconcile company table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile financial year table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile account-group table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile account table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile voucher table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile ledger-lines table in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile audit tables in migration against frozen schema~~  
  Owner: `Review`  
  Depends: release board exists  
  Proof: migration matches frozen schema for touched fields

- ~~Reconcile same tables in `schema_v1.sql` against frozen schema~~  
  Owner: `Review`  
  Depends: migration table reconciliations complete  
  Proof: SQL source matches frozen schema for the same touched tables

- ~~Confirm `MigrationV001.swift` and `schema_v1.sql` match each other~~  
  Owner: `Review`  
  Depends: both schema sources reconciled  
  Proof: no meaningful drift remains between the two schema sources

### D. Repository / Service Correctness
- ~~Ensure voucher post no longer swallows account-usage update failures~~  
  Owner: `Code`  
  Proof: failure path is no longer silently ignored

- ~~Reconcile `CompanyRepository` against frozen schema and rules~~  
  Owner: `Review`  
  Depends: schema reconciliation for company/FY tables  
  Proof: reads/writes use only valid fields and constraints

- ~~Reconcile `FinancialYearRepository` against frozen schema and rules~~  
  Owner: `Review`  
  Depends: schema reconciliation for FY tables  
  Proof: create/list/lock behavior matches rules

- ~~Reconcile `AccountRepository` against frozen schema and rules~~  
  Owner: `Review`  
  Depends: schema reconciliation for account/account-group tables  
  Proof: disable/use/group behavior matches rules

- ~~Reconcile `VoucherRepository` against frozen schema and rules~~  
  Owner: `Review`  
  Depends: schema reconciliation for voucher/ledger tables  
  Proof: write/read/filter behavior matches rules

- ~~Reconcile `AuditRepository` against frozen schema and rules~~  
  Owner: `Review`  
  Depends: schema reconciliation for audit tables  
  Proof: event writes and query behavior match rules

- ~~Reconcile `BackupService` and restore path against frozen rules~~  
  Owner: `Review`  
  Depends: schema reconciliation complete  
  Proof: backup/restore assumptions match actual schema and rules

- ~~Harden voucher posting against known `P0` defects~~  
  Owner: `Code`  
  Depends: voucher repository review  
  Proof: post path handles validation, balancing, lock rules, company scope correctly

- ~~Harden voucher edit against known `P0` defects~~  
  Owner: `Code`  
  Depends: voucher posting hardening  
  Proof: edit path preserves integrity and audit expectations

- ~~Harden voucher reversal against known `P0` defects~~  
  Owner: `Code`  
  Depends: voucher posting hardening  
  Proof: reversal nets correctly and follows rule set

- ~~Verify FY lock enforcement across all voucher and ledger write paths~~  
  Owner: `Test`  
  Depends: voucher hardening complete  
  Proof: locked FY rejects every shipped write path

- ~~Verify audit logging for all financially meaningful actions~~  
  Owner: `Test`  
  Depends: voucher hardening and repository review complete  
  Proof: create/edit/reverse/lock-critical actions emit audit entries

- ~~Verify company isolation~~  
  Owner: `Test`  
  Depends: repository review complete  
  Proof: no cross-company reads or writes occur in shipped flows

- ~~Verify restore integrity~~  
  Owner: `Test`  
  Depends: backup/restore review complete  
  Proof: restored data matches source and loads cleanly

## Blocked By Dependency

### E. Core User Flows
- ~~Return app to clean build after shell migration~~  
  Owner: `Code`  
  Proof: build passes

- ~~Keep automated suite green after shell migration~~  
  Owner: `Test`  
  Proof: tests pass

- ~~Keep company setup flow green after onboarding migration~~  
  Owner: `Test`  
  Proof: onboarding still reaches usable company

- ~~Review company setup flow from first launch to usable company~~  
  Owner: `Manual QA`  
  Depends: observation migration complete  
  Proof: create company, active FY set, dashboard opens

- ~~Review company switching flow~~  
  Owner: `Manual QA`  
  Depends: observation migration complete, company isolation verified  
  Proof: switch updates all visible context correctly

- ~~Review accounts flow~~  
  Owner: `Manual QA`  
  Depends: `AccountsViewModel` migration, account repository review  
  Proof: create/edit/disable/filter works correctly

- ~~Review voucher list flow~~  
  Owner: `Manual QA`  
  Depends: `VouchersViewModel` migration, voucher repository review  
  Proof: list/filter/search behaves correctly

- ~~Review voucher create flow~~  
  Owner: `Manual QA`  
  Depends: `VoucherEditViewModel` migration, voucher posting hardening  
  Proof: valid voucher saves, invalid voucher blocks

- ~~Review voucher edit flow~~  
  Owner: `Manual QA`  
  Depends: voucher edit hardening  
  Proof: edits persist correctly and totals remain valid

- ~~Review voucher reverse flow~~  
  Owner: `Manual QA`  
  Depends: voucher reversal hardening  
  Proof: reversal result is correct and visible in reports/list

- ~~Review settings and FY-management flow~~  
  Owner: `Manual QA`  
  Depends: `SettingsViewModel` migration, FY repository review  
  Proof: FY create/list/lock behavior is correct

- ~~Review backup flow~~  
  Owner: `Manual QA`  
  Depends: backup service review  
  Proof: backup artifact is produced successfully

- ~~Review restore flow~~  
  Owner: `Manual QA`  
  Depends: restore integrity verified  
  Proof: restore completes and reopened company is usable

### F. Reports And Reconciliation
- ~~Correct dashboard summary logic to use real account codes and report totals~~  
  Owner: `Code`  
  Proof: dashboard uses real report/account sources

- ~~Validate trial balance totals against seeded SQL totals~~  
  Owner: `Test`  
  Depends: schema + voucher correctness complete  
  Proof: totals tie to SQL fixture

- ~~Validate trial balance totals against live data totals~~  
  Owner: `Test`  
  Depends: schema + voucher correctness complete  
  Proof: totals tie to live computed SQL

- ~~Validate P&L totals against seeded SQL totals~~  
  Owner: `Test`  
  Depends: account grouping + voucher correctness complete  
  Proof: totals tie to SQL fixture

- ~~Validate P&L totals against live data totals~~  
  Owner: `Test`  
  Depends: account grouping + voucher correctness complete  
  Proof: totals tie to live computed SQL

- ~~Validate balance sheet totals against seeded SQL totals~~  
  Owner: `Test`  
  Depends: account grouping + voucher correctness complete  
  Proof: totals tie to SQL fixture

- ~~Validate balance sheet totals against live data totals~~  
  Owner: `Test`  
  Depends: account grouping + voucher correctness complete  
  Proof: totals tie to live computed SQL

- ~~Validate ledger report behavior~~  
  Owner: `Manual QA`  
  Depends: voucher correctness complete  
  Proof: ledger rows, balances, and date filters are correct

- ~~Validate day book behavior~~  
  Owner: `Manual QA`  
  Depends: voucher correctness complete  
  Proof: row ordering and visible totals are correct

- ~~Validate GST summary behavior~~  
  Owner: `Manual QA`  
  Depends: voucher correctness complete  
  Proof: GST totals and date boundaries are correct

- ~~Validate outstanding behavior~~  
  Owner: `Manual QA`  
  Depends: voucher correctness complete  
  Proof: receivable/payable balances are correct

- ~~Verify report drill-down opens the correct source voucher~~  
  Owner: `Manual QA`  
  Depends: reports load correctly, voucher flows reviewed  
  Proof: clicked row opens correct voucher every time

- ~~Verify report date boundaries respect active FY and lock rules~~  
  Owner: `Test`  
  Depends: FY lock verification complete  
  Proof: no out-of-range data leaks into reports

### G. Regression Protection
- ~~Run `swift build` after completed architecture batches~~  
  Owner: `Test`  
  Proof: build remains green after each batch

- ~~Run `swift test` after completed architecture batches~~  
  Owner: `Test`  
  Proof: tests remain green after each batch

- ~~Fail loudly on malformed UUIDs in shipped V1 row-decode and report paths~~  
  Owner: `Code`  
  Depends: core repository correctness complete  
  Proof: shipped repositories and report decoders reject malformed UUIDs with explicit read failures, and build/tests are green

- ~~Add regression test for silent-delete schema fix~~  
  Owner: `Test`  
  Depends: schema reconciliation for ledger lines complete  
  Proof: test fails if cascade behavior returns

- ~~Add regression test for account-usage update failure handling~~  
  Owner: `Test`  
  Depends: voucher service path stable  
  Proof: test fails if failure becomes silent again

- ~~Add regression tests for validator failure-mode handling~~  
  Owner: `Test`  
  Depends: validation paths complete  
  Proof: validation returns internal errors instead of silently accepting database failures

- ~~Add regression tests for malformed UUID handling in shipped V1 paths~~  
  Owner: `Test`  
  Depends: malformed UUID fail-loud work complete  
  Proof: malformed ID reads fail in tests for core repositories, registry path, and shipped report decoding

- ~~Add regression test for company file delete cleanup~~  
  Owner: `Test`  
  Depends: company file resolution hardening complete  
  Proof: delete path removes registered and legacy company files without swallowing removal failures

- ~~Add regression test for backup export failure handling~~  
  Owner: `Test`  
  Depends: backup export failure handling complete  
  Proof: backup export reports a clean file-system error when the destination path is invalid

- ~~Add regression test for report drill-down routing~~  
  Owner: `Test`  
  Depends: report drill-down path complete  
  Proof: report row drill-down routes to the edit-voucher sheet for the tapped voucher

- ~~Add regression tests for voucher posting `P0` fixes~~  
  Owner: `Test`  
  Depends: posting hardening complete  
  Proof: each fixed posting defect has at least one protecting test

- ~~Add regression tests for voucher edit `P0` fixes~~  
  Owner: `Test`  
  Depends: edit hardening complete  
  Proof: each fixed edit defect has at least one protecting test

- ~~Add regression tests for voucher reversal `P0` fixes~~  
  Owner: `Test`  
  Depends: reversal hardening complete  
  Proof: each fixed reversal defect has at least one protecting test

- ~~Add repository tests for schema-sensitive paths~~  
  Owner: `Test`  
  Depends: repository reviews complete  
  Proof: repository assumptions are covered in tests

- ~~Add service tests for FY lock enforcement~~  
  Owner: `Test`  
  Depends: FY verification complete  
  Proof: lock bypasses fail in tests

- ~~Add service tests for audit writes~~  
  Owner: `Test`  
  Depends: audit verification complete  
  Proof: missing audit write causes test failure

- ~~Add tests for company isolation~~  
  Owner: `Test`  
  Depends: company isolation verification complete  
  Proof: cross-company leakage causes test failure

- ~~Add tests for backup/restore roundtrip~~  
  Owner: `Test`  
  Depends: restore integrity verification complete  
  Proof: restore mismatch causes test failure

- ~~Add targeted report reconciliation tests~~  
  Owner: `Test`  
  Depends: report validation complete  
  Proof: report mismatch causes test failure

## Deferred / Conditional

### H. Conditional Modules
- ~~Audit inventory and decide `ship` or `defer`~~  
  Owner: `Decision`  
  Depends: core release path substantially green  
  Proof: module is explicitly kept or removed from `v1` and hidden from V1 shell entry points

- ~~Audit payroll and decide `ship` or `defer`~~  
  Owner: `Decision`  
  Depends: core release path substantially green  
  Proof: module is explicitly kept or removed from `v1` and hidden from V1 shell entry points

- ~~Audit banking and decide `ship` or `defer`~~  
  Owner: `Decision`  
  Depends: core release path substantially green  
  Proof: module is explicitly kept or removed from `v1` and hidden from V1 shell entry points

- ~~Audit advanced GST export and decide `ship` or `defer`~~  
  Owner: `Decision`  
  Depends: core release path substantially green  
  Proof: module is explicitly kept or removed from `v1` and hidden from V1 shell entry points

## Final Release Path

### I. Manual QA And Release Gates
- ~~Run accountant-style QA for company setup~~  
  Owner: `Manual QA`  
  Depends: user-flow review complete  
  Proof: no blocker found in setup path

- ~~Run accountant-style QA for accounts~~  
  Owner: `Manual QA`  
  Depends: accounts flow review complete  
  Proof: no blocker found in account path

- ~~Run accountant-style QA for voucher posting, edit, reversal~~  
  Owner: `Manual QA`  
  Depends: voucher flow reviews complete  
  Proof: no blocker found in voucher path

- ~~Run accountant-style QA for FY lock behavior~~  
  Owner: `Manual QA`  
  Depends: FY lock verification complete  
  Proof: no blocker found in FY lock path

- ~~Run accountant-style QA for reports~~  
  Owner: `Manual QA`  
  Depends: report validation complete  
  Proof: no blocker found in report path

- ~~Run accountant-style QA for backup/restore~~  
  Owner: `Manual QA`  
  Depends: backup/restore flow review complete  
  Proof: no blocker found in backup/restore path

- ~~Confirm zero known `P0` bugs in shipped scope~~  
  Owner: `Decision`  
  Depends: all core tracks green  
  Proof: execution board has zero open `P0` in shipped path

- ~~Confirm zero known silent data-loss or silent deletion paths~~  
  Owner: `Decision`  
  Depends: schema and restore checks green  
  Proof: no open issue remains in this class

- ~~Confirm zero known FY lock bypasses~~  
  Owner: `Decision`  
  Depends: FY verification and tests green  
  Proof: no open lock-bypass issue remains

- ~~Confirm zero network behavior in shipped app~~  
  Owner: `Review`  
  Depends: final shipped scope fixed  
  Proof: no shipped network stack usage remains

- ~~Confirm core reports reconcile on validation data~~  
  Owner: `Decision`  
  Depends: report validations and tests green  
  Proof: validation runs are green

### J. Stress, Soak, RC, Deployment
- ~~Run voucher-volume stress checks~~  
  Owner: `Test`  
  Depends: core release gates nearly green  
  Proof: no crash or corruption under volume

- ~~Run repeated report-generation stress checks~~  
  Owner: `Test`  
  Depends: report validations green  
  Proof: repeated generation stays stable and correct

- ~~Run company-switching soak checks~~  
  Owner: `Test`  
  Depends: company switching flow reviewed  
  Proof: repeated switching remains stable

- ~~Run restore/reopen soak checks~~  
  Owner: `Test`  
  Depends: restore flow reviewed  
  Proof: repeated restore/reopen remains stable

- ~~Freeze features for release candidate~~  
  Owner: `Decision`  
  Depends: all core functional work complete  
  Proof: only release blockers may change after this point

- ~~Re-run full verification on release candidate~~  
  Owner: `Test`  
  Depends: RC freeze complete  
  Proof: build, tests, flow checks, and release gates still pass

- ~~Validate deployment package~~  
  Owner: `Test`  
  Depends: RC verification green  
  Proof: deployment artifact is valid for chosen distribution path

- ~~Final go / no-go decision~~  
  Owner: `Decision`  
  Depends: all release gates green  
  Proof: explicit ship decision recorded

## Parallel Work Rules
- Safe parallel work in `B`: independent view-model migrations, but remove each holder only after its paired migration is green.
- Safe parallel work in `C`: schema table reconciliation can run in parallel by table family, but `schema_v1.sql` must not be finalized before migration review is complete.
- Safe parallel work in `D`: company/accounts/settings-backup reviews can run together; voucher create/edit/reverse should stay grouped.
- Safe parallel work in `F`: repository tests, service tests, and report tests can be added in parallel if they do not share fixtures or business-rule edits.
- No parallel work is allowed across items that mutate the same write-path, the same schema contract, or the same report contract.

## Re-Check Rules
- If schema changes after a repository item is struck through, re-check that repository item.
- If voucher write logic changes after a report item is struck through, re-check affected reports.
- If FY logic changes after a flow or report item is struck through, re-check those items.
- If restore logic changes after company or report items are struck through, re-check those items.
- If shell observation changes after a flow item is struck through, re-check the affected UI flow.

## Done Right Now
- ~~Freeze `v1` scope around core accounting, reports, audit, backup/restore, and offline shell~~
- ~~Treat inventory, payroll, banking, and advanced GST as conditional ship only~~
- ~~Create repo-tracked `P0/P1/P2` execution board~~
- ~~Record top 10 blockers in execution order~~
- ~~Mark deferred modules and hidden entry points explicitly~~
- ~~Migrate `AppEnvironment`, `AppRouter`, and `WindowState` to `@Observable`~~
- ~~Move app composition root from `environmentObject` to typed environment injection~~
- ~~Migrate shell views to typed environment access~~
- ~~Migrate `KeyboardBridge` and `KeyboardRouter`~~
- ~~Migrate `AccountTreeCache`~~
- ~~Remove `EnvironmentObject` usage from shipped shell and main feature entry screens~~
- ~~Migrate `OnboardingViewModel`~~
- ~~Migrate `DashboardViewModel`~~
- ~~Migrate `AccountsViewModel`~~
- ~~Remove `AccountsViewModelHolder`~~
- ~~Migrate `ReportsViewModel`~~
- ~~Remove `ReportsViewModelHolder`~~
- ~~Migrate `VouchersViewModel`~~
- ~~Remove `VouchersViewModelHolder`~~
- ~~Migrate `VoucherEditViewModel`~~
- ~~Remove `VoucherEditHolder`~~
- ~~Migrate `SettingsViewModel`~~
- ~~Migrate `AuditViewModel`~~
- ~~Remove `AuditViewModelHolder`~~
- ~~Confirm no shipped workflow mixes old and new observation systems~~
- ~~Remove silent-delete schema violation on `avelo_ledger_lines.voucher_id`~~
- ~~Reconcile company table in migration against frozen schema~~
- ~~Reconcile financial year table in migration against frozen schema~~
- ~~Reconcile account-group table in migration against frozen schema~~
- ~~Reconcile account table in migration against frozen schema~~
- ~~Reconcile voucher table in migration against frozen schema~~
- ~~Reconcile ledger-lines table in migration against frozen schema~~
- ~~Reconcile audit tables in migration against frozen schema~~
- ~~Reconcile same tables in `schema_v1.sql` against frozen schema~~
- ~~Confirm `MigrationV001.swift` and `schema_v1.sql` match each other~~
- ~~Reconcile `CompanyRepository` against frozen schema and rules~~
- ~~Reconcile `FinancialYearRepository` against frozen schema and rules~~
- ~~Reconcile `AccountRepository` against frozen schema and rules~~
- ~~Reconcile `VoucherRepository` against frozen schema and rules~~
- ~~Reconcile `AuditRepository` against frozen schema and rules~~
- ~~Reconcile `BackupService` and restore path against frozen rules~~
- ~~Ensure voucher post no longer swallows account-usage update failures~~
- ~~Harden voucher posting against known `P0` defects~~
- ~~Harden voucher edit against known `P0` defects~~
- ~~Harden voucher reversal against known `P0` defects~~
- ~~Verify FY lock enforcement across all voucher and ledger write paths~~
- ~~Verify audit logging for all financially meaningful actions~~
- ~~Verify company isolation~~
- ~~Verify restore integrity~~
- ~~Fail loudly on malformed UUIDs in shipped V1 row-decode and report paths~~
- ~~Add regression tests for malformed UUID handling in shipped V1 paths~~
- ~~Add regression test for silent-delete schema fix~~
- ~~Add regression test for account-usage update failure handling~~
- ~~Add regression tests for voucher posting `P0` fixes~~
- ~~Add regression tests for voucher edit `P0` fixes~~
- ~~Add regression tests for voucher reversal `P0` fixes~~
- ~~Add service tests for FY lock enforcement~~
- ~~Add service tests for audit writes~~
- ~~Add tests for company isolation~~
- ~~Add tests for backup/restore roundtrip~~
- ~~Validate day book behavior~~
- ~~Validate GST summary behavior~~
- ~~Validate outstanding behavior~~
- ~~Verify report date boundaries respect active FY and lock rules~~
- ~~Add targeted report reconciliation tests~~
- ~~Correct dashboard summary logic to use real account codes and report totals~~
- ~~Return app to clean build after shell migration~~
- ~~Keep automated suite green after shell migration~~
- ~~Keep company setup flow green after onboarding migration~~
- ~~Run `swift build` after completed architecture batches~~
- ~~Run `swift test` after completed architecture batches~~

## Immediate Next Sequence
1. Finish `B. Observation / Shell Completion`.
2. Finish `C. Schema Source Of Truth`.
3. Finish `D. Repository / Service Correctness`.
4. Run `E. Core User Flows`.
5. Run `F. Reports And Reconciliation`.
6. Close `G. Regression Protection`.
7. Decide `H. Conditional Modules`.
8. Run `I. Manual QA And Release Gates`.
9. Run `J. Stress, Soak, RC, Deployment`.

## Definition Of Done
Strike an item only when:
- the work is complete
- its `Proof` is satisfied
- `swift build` and `swift test` are green for code-changing work
- required dependency re-checks are green
- no known blocker remains for that item
