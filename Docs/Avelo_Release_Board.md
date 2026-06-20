# AVELO Release Board

This is the repo-tracked `P0/P1/P2` execution board for the release push. Each open issue appears once, carries one severity, and maps back to the master execution checklist.

Current release target:
- `v1.1` is the performance, accuracy, and reliability hardening release.
- The current benchmark focus is on repeatable local measurement for cold launch, core voucher/report paths, backup/restore, soak, stress, and million-voucher runs on the same machine and dataset.

Severity rules:
- `P0`: release-blocking correctness, data integrity, fiscal lock, restore, or core offline-behavior risk
- `P1`: high-priority shipped-path gap that can cause broken workflow, bad UX trust, or incomplete validation
- `P2`: lower-priority release work, deferrable module decisions, or hardening/polish items that do not block core correctness by themselves

Module ship status:
- `Core ship`: company setup, company switching, FYs, accounts, vouchers, reports, inventory, payroll, banking, audit, backup/restore, offline shell
- `Conditional`: none in the current local RC shell
- `Deferred`: PO/SO order-tracking, cash flow statement, stock ageing/reorder alerts, group-company consolidation, and invoice-wise GSTR-1 portal upload data beyond the current summary CSV/report preparation; each requires either a new report family or a cross-file/stateful workflow layer that exceeds the RC scope

Release split rule:
- If it affects correctness, data loss, or the app's ability to open and save reliably on day one, it belongs in `V1`.
- If it improves offline merge, security, scale, or benchmark tooling but does not block launch, it belongs in `V2`.
- If it is mainly enterprise hardening, resilience polish, or rare-edge-case protection, it belongs in `V3`.

## Release Split

### V1: Must Ship
- Fail loudly on malformed UUIDs instead of substituting fresh IDs. Status: done in shipped repository, registry, and report-decode paths with regression coverage.
- Keep restore safe and deterministic; minimize mutation during restore and preserve checksum verification.
- Preserve core correctness guarantees already in place: WAL, foreign keys, transactions, locked fiscal years, audit immutability, company isolation.
- `VoucherService.postBatch` commits in bounded chunks of 500 drafts; if a later chunk fails, already-committed chunks remain durable and the failing/later chunks are not partially persisted.
- Add basic handling for missing or moved company files that gives a clear recovery path or explicit re-link workflow. Status: core open and backup paths now honor registry `sqlite_file_name`, preserve a legacy `id.sqlite` fallback, and fail with explicit re-link or restore guidance when the registered file is missing.
- Add minimum viability checks for permissions, disk-full, and backup-write failures so the app fails cleanly.
- Prevent obvious large-ledger or report slow paths that would make core accounting unusable at launch.

### V2: Should Ship After Launch
- Migrate from plain UUIDs to UUIDv7 for time-sortable IDs and better offline merge behavior.
- Add stronger restore hardening and more explicit integrity verification around imported backups.
- Add basic large-dataset performance work: better pagination, query-plan tuning, prepared-statement reuse, and benchmark-driven regression checks.
- SQLCipher at-rest encryption is active for app-managed company databases with per-company raw keys stored in Keychain and user-custody recovery keys for cross-machine restore.
- Add clearer recovery for unusual filesystem cases like network volumes or antivirus locks.

### V3: Later Hardening / Scale Work
- Filesystem-type detection and FAT32-specific backup warnings.
- Thermal-throttling-aware UI behavior.
- `VACUUM` / `ANALYZE` automation and other maintenance jobs.
- Materialized rollups and advanced reporting acceleration.
- Deep UI virtualization and more aggressive memory-load shedding.
- Niche hardware-edge-case protections such as serial-port bounds checks or cosmic-ray-style fault mitigation.

Hidden entry-point rule:
- Conditional or deferred modules must not remain exposed in the shipped release path unless they pass the same gates as core ship.
- Current hidden-entry-point review targets: sidebar routes, command palette items, quick search hits, menu items, and sheet entry points for advanced GST export actions.

## Top 10 Blockers In Execution Order

1. No current release blockers proven from repo evidence

## Release-Risk Split

| Track | Status | Notes |
| --- | --- | --- |
| V1 | Active | Day-one correctness, restore safety, file-open/save reliability, and launch viability risks stay here until closed. |
| V2 | Deferred until post-launch unless needed to unblock V1 | Merge behavior, stronger backup integrity, at-rest encryption, and broader scale tuning belong here. |
| V3 | Deferred | Edge-case resilience, maintenance automation, and deep scale or hardware hardening belong here. |

## Open Board

| ID | Severity | Status | Checklist Ref | Issue |
| --- | --- | --- | --- | --- |
| RB-001 | P0 | Done | B | Migrate `AccountsViewModel` and remove `AccountsViewModelHolder` |
| RB-002 | P0 | Done | B | Migrate `ReportsViewModel` and remove `ReportsViewModelHolder` |
| RB-003 | P0 | Done | B | Migrate `VouchersViewModel` and remove `VouchersViewModelHolder` |
| RB-004 | P0 | Done | B | Migrate `VoucherEditViewModel` and remove `VoucherEditHolder` |
| RB-005 | P0 | Done | B | Migrate `SettingsViewModel` |
| RB-006 | P0 | Done | B | Migrate `AuditViewModel` and remove `AuditViewModelHolder` |
| RB-007 | P0 | Done | B | Confirm no shipped workflow mixes old and new observation systems |
| RB-008 | P0 | Done | C | Reconcile company and financial-year tables in migration against frozen schema |
| RB-009 | P0 | Done | C | Reconcile account-group and account tables in migration against frozen schema |
| RB-010 | P0 | Done | C | Reconcile voucher and ledger-lines tables in migration against frozen schema |
| RB-011 | P0 | Done | C | Reconcile audit tables in migration against frozen schema, including the frozen allowed-action set |
| RB-012 | P0 | Done | C | Reconcile matching tables in `schema_v1.sql` against frozen schema |
| RB-013 | P0 | Done | C | Confirm `MigrationV001.swift` and `schema_v1.sql` match each other |
| RB-014 | P0 | Done | D | Reconcile `CompanyRepository` and `FinancialYearRepository` against frozen schema/rules |
| RB-015 | P0 | Done | D | Reconcile `AccountRepository` against frozen schema/rules |
| RB-016 | P0 | Done | D | Reconcile `VoucherRepository` against frozen schema/rules |
| RB-017 | P0 | Done | D | Reconcile `AuditRepository` against frozen schema/rules |
| RB-018 | P0 | Done | D | Reconcile `BackupService` and restore path against frozen rules |
| RB-019 | P0 | Done | D | Harden voucher posting against known `P0` defects |
| RB-020 | P0 | Done | D | Harden voucher edit against known `P0` defects |
| RB-021 | P0 | Done | D | Harden voucher reversal against known `P0` defects |
| RB-022 | P0 | Done | D | Verify FY lock enforcement across all shipped write paths |
| RB-023 | P0 | Done | D | Verify audit logging for all financially meaningful actions |
| RB-024 | P0 | Done | D | Verify company isolation |
| RB-025 | P0 | Done | D | Verify restore integrity |
| RB-026 | P1 | Done | E | Review company setup and switching shipped flows |
| RB-027 | P1 | Done | E | Review accounts shipped flow |
| RB-028 | P1 | Done | E | Review voucher list/create/edit/reverse shipped flows |
| RB-029 | P1 | Done | E | Review settings/FY-management shipped flow |
| RB-030 | P1 | Done | E | Review backup/restore shipped flows |
| RB-031 | P1 | Done | F | Validate trial balance totals against seeded and live SQL totals |
| RB-032 | P1 | Done | F | Validate P&L totals against seeded and live SQL totals |
| RB-033 | P1 | Done | F | Validate balance sheet totals against seeded and live SQL totals |
| RB-034 | P1 | Done | F | Validate ledger, day book, GST summary, and outstanding behavior |
| RB-035 | P1 | Done | F | Verify report drill-down opens the correct source voucher |
| RB-036 | P1 | Done | G | Add regression tests for schema-sensitive and accounting-sensitive fixes |
| RB-037 | P1 | Done | I | Run manual accountant-style QA for shipped scope |
| RB-038 | P2 | Done | H | Inventory audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-039 | P2 | Done | H | Payroll audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-040 | P2 | Done | H | Banking audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-041 | P2 | Done | H | Advanced GST export audited and kept deferred from V1 shell entry points |
| RB-043 | P1 | Done | J | Prove promoted inventory, payroll, and banking shell routes behave correctly across sidebar, menu, keyboard, and command palette |
| RB-042 | P2 | Done | J | Run stress, soak, RC, and deployment validation |
| RB-048 | P2 | Done | J | Benchmark harness and 500k stress validation completed with before/after JSON and post-cleanup memory gate proof |

## Completed Board Items

| ID | Severity | Checklist Ref | Completed Item |
| --- | --- | --- | --- |
| RB-D01 | P0 | B | `AppEnvironment`, `AppRouter`, and `WindowState` migrated to `@Observable` |
| RB-D02 | P0 | B | App composition root moved from `environmentObject` to typed environment injection |
| RB-D03 | P0 | B | Shell views migrated to typed environment access |
| RB-D04 | P0 | B | `KeyboardBridge`, `KeyboardRouter`, and `AccountTreeCache` migrated |
| RB-D05 | P0 | B | `OnboardingViewModel` and `DashboardViewModel` migrated |
| RB-D05A | P0 | B | `AccountsViewModel` migrated and `AccountsViewModelHolder` removed |
| RB-D05B | P0 | B | `ReportsViewModel` migrated and `ReportsViewModelHolder` removed |
| RB-D05BB | P0 | B | `VouchersViewModel` migrated and `VouchersViewModelHolder` removed |
| RB-D05BC | P0 | B | `VoucherEditViewModel` migrated and `VoucherEditHolder` removed |
| RB-D05C | P0 | B | `SettingsViewModel` migrated |
| RB-D05D | P0 | B | `AuditViewModel` migrated and `AuditViewModelHolder` removed |
| RB-D05E | P0 | B | Shipped release path no longer mixes old and new observation systems |
| RB-D06 | P0 | C | Silent-delete schema violation on `avelo_ledger_lines.voucher_id` removed |
| RB-D06A | P0 | C | Company and financial-year migration tables reconciled to frozen schema |
| RB-D06B | P0 | C | Account-group and account migration tables reconciled to frozen schema |
| RB-D06C | P0 | C | Voucher and ledger-lines migration tables reconciled to frozen schema |
| RB-D06D | P0 | C | Audit migration table reconciled to frozen schema, including allowed action constraint |
| RB-D06E | P0 | C | `schema_v1.sql` reconciled to frozen schema for current checklist tables |
| RB-D06F | P0 | C | `MigrationV001.swift` and `schema_v1.sql` now match for the current checklist scope |
| RB-D07A | P0 | D | `CompanyRepository` and `FinancialYearRepository` reconciled against frozen schema/rules |
| RB-D07B | P0 | D | `AccountRepository` reconciled against frozen schema/rules |
| RB-D07C | P0 | D | `VoucherRepository` reconciled against frozen schema/rules |
| RB-D07D | P0 | D | `AuditRepository` reconciled against frozen schema/rules |
| RB-D07E | P0 | D | `BackupService` and restore path reconciled against frozen rules |
| RB-D07 | P0 | D | Voucher post no longer swallows account-usage update failures |
| RB-D07F | P0 | D | Voucher posting hardened for validation, account usage, and audit snapshot correctness |
| RB-D07G | P0 | D | Voucher edit hardened for locked-FY rejection and full audit snapshots |
| RB-D07H | P0 | D | Voucher reversal hardened for locked-FY flow, duplicate reversal blocking, and audit snapshots |
| RB-D07I | P0 | D | FY lock enforcement verified across shipped voucher write paths |
| RB-D07J | P0 | D | Audit logging verified for voucher lifecycle and FY lock actions |
| RB-D07K | P0 | D | Company isolation verified for shipped voucher reads and writes |
| RB-D07L | P0 | D | Backup/restore integrity verified with end-to-end roundtrip and preserved audit history |
| RB-D08 | P1 | F | Dashboard summary logic corrected to use real account codes and report totals |
| RB-D09 | P1 | E | App brought back to clean build after shell migration |
| RB-D10 | P1 | E | Automated suite kept green after shell migration |
| RB-D11 | P1 | E | Company setup flow kept green after onboarding migration |
| RB-D12 | P0 | G | Malformed UUIDs now fail loudly in shipped repository, registry, and report decode paths, with regression tests guarding the behavior |
| RB-D13 | P0 | G | Silent-delete regression coverage added to prove voucher deletes do not cascade ledger lines |
| RB-D14 | P0 | G | Account-usage update failures now fail closed and are guarded by repository and transaction rollback tests |
| RB-D15 | P0 | G | Voucher post, edit, and reversal `P0` hardening now have rollback and invariant regression coverage |
| RB-D16 | P0 | G | FY lock enforcement is guarded by service-level tests for post, edit, and reversal behavior |
| RB-D17 | P0 | G | Audit write expectations are guarded by voucher lifecycle and restore tests |
| RB-D18 | P0 | G | Company isolation is guarded by shipped voucher read/write tests |
| RB-D19 | P0 | G | Backup/restore roundtrip is guarded by end-to-end restore tests |
| RB-D20 | P1 | F | Trial balance totals are now guarded by seeded expected-value and live SQL reconciliation tests |
| RB-D21 | P1 | F | P&L totals are now guarded by seeded expected-value and live SQL reconciliation tests on the real default chart shape |
| RB-D22 | P1 | F | Balance sheet totals are now guarded by seeded expected-value and live SQL reconciliation tests for the shipped balance-sheet model |
| RB-D23 | P1 | F | Day book behavior is guarded by range and ordering tests on seeded report activity |
| RB-D24 | P1 | F | Outstanding report now uses the correct debtor/creditor account codes and is guarded by direction and as-of tests |
| RB-D25 | P1 | F | GST summary sign handling is fixed and guarded by seeded bucket/date-range tests |
| RB-D26 | P1 | F | Report date-boundary coverage now guards trial balance, day book, and GST filtering against later activity leakage |
| RB-D27 | P1 | G | Targeted report reconciliation and behavior tests now cover trial balance, P&L, balance sheet, day book, GST summary, outstanding, and report date boundaries |
| RB-D28 | P1 | F | Ledger report behavior is now guarded by running-balance, date-range, and source-voucher-linkage tests |
| RB-D29 | P0 | V1 | Company open and backup paths now honor registry-tracked SQLite file names, preserve legacy `id.sqlite` fallback, and fail clearly when a registered file is missing |
| RB-D30 | P1 | E | Company create/open and company-switch flow behavior is now guarded by environment-level tests that prove usable context setup, router reset, and visible company-state swap |
| RB-D31 | P1 | E | Restore flow now auto-opens the restored company and is guarded by environment-level proof that a restored company lands in a usable context |
| RB-D32 | P1 | E | Open-company, new-account, new-voucher, and edit-voucher shipped UI paths now surface typed errors instead of silently swallowing repository/service failures |
| RB-D33 | P1 | G | Account and voucher validation now fail with internal validation errors instead of silently accepting database lookup failures, guarded by failure-mode tests |
| RB-D34 | P2 | G | Report repository query paths now throw instead of silently degrading aggregate calculations to zero when the database query fails |
| RB-D35 | P1 | D | Company file delete cleanup now fails loudly on removal errors and is guarded by regression coverage for registered and legacy file removal |
| RB-D36 | P1 | D | Backup export now reports file-system errors cleanly when the destination path is invalid and is guarded by regression coverage |
| RB-D37 | P1 | F | Report drill-down routing now explicitly targets the edit-voucher sheet for tapped report rows and is guarded by regression coverage |
| RB-D38 | P2 | J | Added a reproducible `Scripts/bundle.sh` app-bundle path, validated `dist/Avelo.app` launches locally, and fixed the shipped invalid SF Symbol on the dashboard quick actions |
| RB-D39 | P2 | J | Added automated RC stress coverage for voucher volume and repeated report generation, and proved both checks green |
| RB-D40 | P2 | J | Expanded RC local-failure coverage for startup degradation, close-company cleanup, backup replacement failure, and duplicate-restore rejection |
| RB-D41 | P2 | J | Added repeatable bundle validation with ad-hoc signing and structural verification for the local RC distribution artifact |
| RB-D42 | P1 | J | Promoted inventory, payroll, and banking routes now work across shipped shell entry points, with keyboard routing regression coverage and aligned menu shortcuts |
| RB-D43 | P1 | B | Inventory, payroll, and banking now use the same `@Observable` shipped-shell pattern as the rest of the core release path, and `make rule-audit` keeps those promoted modules excluded from the shipped-surface R-16 audit |
| RB-D44 | P2 | J | Added a repeatable bundled-app launch smoke check and proved `dist/Avelo.app` launches and stays alive locally when run outside the sandbox |
| RB-D45 | P2 | J | Restore now has explicit regression coverage for a non-writable destination company directory, further narrowing the remaining local file-handling RC risk |
| RB-D46 | P1 | I/J | Added an integrated accountant RC flow test that creates and opens a real company, creates an account, posts/edits/reverses vouchers, locks FY, validates reports, and round-trips backup/restore end to end |
| RB-D47 | P1 | D/J | Restore now succeeds even when the source company contains locked financial years, by suspending locked-FY voucher/ledger triggers only during the controlled restore remap window |
