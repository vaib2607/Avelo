# Avelo Status Checklist

Snapshot: 2026-07-19

This is the human-readable progress checklist for Avelo. It complements:

- `Docs/Avelo_Release_Board.md` — canonical issue-level readiness board.
- `Docs/Avelo_Execution_Checklist.md` — remaining `AVL-*` delivery queue.

The consolidated product and execution roadmap is `Docs/Avelo_Master_Product_Execution_Plan.md`. This checklist records evidence only and must not convert roadmap intent into completion claims.

Checkboxes show evidence, not aspiration: `[x]` means implemented with recorded automated evidence, not necessarily release-accepted; `[ ]` still needs implementation, re-verification, or human acceptance. A feature is not release-ready until current-worktree automated proof and every required accountant, operator, keyboard, accessibility, visual, and distribution gate are complete.

Status maintenance contract:

- The first section always identifies branch/base commit, clean or dirty state, schema version, evidence timestamp/timezone, commands, skipped tests, and artifact identity.
- Evidence from an older commit or artifact is labelled historical; it never receives the word `current` after source, migration, test, resource, entitlement, or build-setting changes.
- Feature summaries reuse canonical `AVL-*` IDs and separate implementation, automated proof, manual acceptance, and external distribution state.
- Test counts are evidence snapshots, not durable product facts. Prefer command/result plus identity, and retain old counts only when needed for provenance.
- Update this file after the release board and execution checklist, then run `make docs-check`.

## 0. Active worktree and evidence identity — 2026-07-19

Active state: `main` based at `93eb199`, with an intentionally dirty V027–V030 accounting/inventory/report/voucher slice. `SchemaVersion.current` is V030. Current automated evidence: `make test`, `make rule-audit`, and `make rc-local` passed on 2026-07-19 Asia/Kolkata; `make bundle`, validation, bundle self-test, and `make launch-smoke` passed. Bundle executable SHA-256: `25a702c569d0fcfbe0986d6ff5da18499a6e36abf10b162f3f70bc94aa22e8ec`; it remains ad-hoc signed. V027 remains `Proof remaining` because direct integrity/parity matrices and all human acceptance gates are not complete.

The checked evidence immediately below was captured on 2026-07-18 Asia/Kolkata for clean `main` at `93eb199`. It is retained as historical baseline and does not prove the active V027–V029 worktree.

- [x] Stabilized high-volume voucher posting: transaction-scoped draft validation, bounded multi-row voucher/ledger/audit inserts, and contiguous HMAC audit-chain batching now preserve per-voucher accounting and rollback semantics while removing the prior encrypted batch-post performance regression.
- [x] Added audit-chain safeguards and regression coverage: checked sequence arithmetic, one-company batch validation, duplicate-event rollback, cross-chunk continuity, and post-failure next-sequence checks.
- [x] Added voucher-batch regression coverage for inactive accounts, locked financial years, cash/bank eligibility, and chunk rollback behavior.
- [x] Fixed the headless backup-cleanup test to use `InMemoryCompanyKeyStore`, matching the rest of the test suite and avoiding a real-Keychain `SecItemAdd` block during legacy-key migration. The focused test passed in 0.300s.
- [x] Targeted audit/voucher regression command passed: 54 tests, 0 failures.
- [x] All opt-in `PerformanceBenchmarkTests` passed: account-tree reload 0.094s; encrypted post-batch 10k 5.246s (limit 9.037s); encrypted post-batch 100k 98.944s (limit 106.381s); encrypted 50k reporting checks passed.
- [x] `git diff --check` passed for the current tracked diff.
- [x] Baseline `make test` passed on 2026-07-18. The test catalogue contained 524 XCTest cases; no skipped or failed case was reported by the supported command.
- [x] Baseline `make rule-audit` and `make rc-local` passed on 2026-07-18: network, R-16, R-15, and automated R-4 checks clean; release bundle assembly, validation, and bundle self-test passed. The rule audit still names its required manual checks.
- [x] `make benchmark` and `make benchmark-million` passed on 2026-07-18. Sandbox-only SwiftPM cache warnings and existing vendored SQLCipher `MIN`/`MAX` macro warnings occurred; neither failed the gates.
- [x] `make launch-smoke` passed against `dist/Avelo.app` on 2026-07-18. It validates and self-tests the bundle; it does not open a GUI window.
- [x] Evidence identity: 2026-07-18 Asia/Kolkata; `main` `93eb199`; macOS 15.4.1 (24E263), Xcode 16.4, Swift 6.1.2, x86_64; `dist/Avelo.app` executable SHA-256 `19a6335d8687e3e9659b2b36732786af6010628e4d2d2b03a837150f39e7d3af`, ad-hoc signature, no Team ID.
- [x] UI audit #9b Balance Sheet pass: selection, as-of change, comparative mode, Refresh, and shortcuts use one load path. A failed selected-FY/as-of request clears prior rows and renders a local Reports error with retry; it never renders empty success or uses a global alert. Balance Sheet validates the selected company/FY/as-of scope before cache/query and reconciles only that scope. `BalanceSheetReconciliationTests` 7/0 and `ReportsViewModelTests` 11/0 pass. Manual macOS keyboard, visual, and accountant acceptance remain.
- [x] Warning-free production compilation passed with `-Xswiftc -warnings-as-errors`; warnings found by a clean benchmark build were removed and focused regressions passed.
- [x] Standard benchmark passed: 25k fixture 118.149s, 500 additional posts 2.272s, report bundle 6.048s, backup export 0.018s, and restore 0.038s.
- [x] The explicit 500k large-data gate passed: batched posting 760.548s, financial report pass 21.969s, balanced books, approximately 140 MB reported resident memory, and no test failure.
- [ ] Developer ID signing, hardened-runtime/entitlement review, notarization, stapling, downloadable-artifact verification, and clean-machine install/upgrade acceptance remain external distribution gates.

### 0.1 Reconciled post-`dee4ac6` workflow status

| ID / scope | State | Evidence on `main` | Residual work |
| --- | --- | --- | --- |
| `AVL-P1-017` multi-window | Proof remaining | `6549675`; `AppEnvironmentFlowTests.testTwoIndependentEnvironmentsOnSharedStorageDoNotLeakCompanyContext` passed. | Editor/draft restoration and two-window stress/acceptance remain. |
| `AVL-P1-025` undo/redo | Implementation remaining | No `UndoManager` or voucher-grid resync implementation exists. | Design and implement the complete feature. |
| `AVL-P1-026` Alt+C master creation | Manual acceptance remaining | `NewVoucherAccountCreationTests` 2/0 proves eligibility rejection plus select-and-preserve-draft flow; full suite and RC proof pass. | Keyboard focus-return, audit visibility, and draft-preservation acceptance in bundled GUI. |
| `AVL-P1-036` comparative reports | Implementation remaining | `d405772`; `ReportsViewModelTests` 9/0 proves prior-year trial balance, P&L, and balance-sheet reconciliation. | General multi-period selection/configuration and accountant report acceptance. |
| `AVL-P1-037` Day Book | Implementation remaining | `017ad13` adds Edit/Reverse row actions. | Universal voucher coverage, cancel/date navigation, drill/return state, tests, and accountant acceptance. |
| `AVL-P2-011` duplicate voucher | Proof remaining | Draft-copy implementation and `VoucherDraftTests` coverage exist. | Explicit posted-flow lineage/fresh-number proof and accountant acceptance. |
| `AVL-P2-012` narration recall | Proof remaining | Company-scoped repository query and repository coverage exist. | Editor shortcut-context/privacy acceptance. |
| `AVL-P2-013` Ctrl+I, PgUp/PgDn | Implementation remaining | `1d0be6d`; `VouchersViewModelTests` 6/0 proves page-local navigation/filter preservation. | List selection/scroll state, unsaved-state guard, text-input precedence, and accountant browse-flow acceptance. |
| UI audit `07bbfb1` plus #9b/#10 | Implemented / manual acceptance remaining | Fixes #1–#9a and #11 are on `main`; #9b now validates selected company/FY/as-of scope and surfaces local report failures instead of empty success. Eligible new Sales/Purchase vouchers now default to explicit item-invoice mode while retaining the visible ledger-mode toggle. | Visual, keyboard, and accountant report acceptance remain. |
| `AVL-P1-045` V027–V030 canonical tracks | Proof remaining | `trn_accounting` and `trn_inventory` are canonical repository/report sources; V028 completes item-invoice draft recovery; V029 adds canonical FY locks; V030 adds audited exact-quantity landed-cost allocation and service-only partial-return commands. `V027MigrationParityTests` proves populated V026 backfill plus unbalanced/malformed-ID fail-closed rollback; `RestoreServiceTests/testRestorePreservesCanonicalTracksAndAllocationLinks` proves canonical remap; `InventoryCostAllocationServiceTests` and `ItemInvoiceReturnServiceTests` prove allocation/return rollback, cross-company rejection, partial return, item-invoice reverse/cancel. `make test` and `make rule-audit` pass. | Full direct FK/CHECK/staged-boundary matrix, full valuation/reversal/export reconciliation proof, final RC/bundle benchmark evidence, and manual accountant/operator/GUI/keyboard/accessibility acceptance remain. |

## 1. Foundation and safety — implemented; release acceptance pending

- [x] Native macOS app built with SwiftUI and SwiftPM.
- [x] Strictly offline product: no network APIs, telemetry, or external Swift packages.
- [x] SQLite is the source of truth, with SQLCipher encryption for app-managed company databases.
- [x] Per-company encryption keys are stored in Keychain; recovery keys support cross-machine restore.
- [x] Multi-company registry, create/open/switch/delete flows, backup, restore, and safe staging paths exist.
- [ ] `AVL-P0-036`: implementation and automated proof are landed. Cross-identity restore remaps `avelo_voucher_item_lines` and `avelo_party_profiles`, intentionally discards scratch drafts, and the real-schema V14–V22 matrix upgrades and remaps FY openings, bills, cheques, BOMs, vouchers, ledger/stock/item/profile rows, dynamically checks every current `company_id` table for source-ID leakage, verifies foreign keys and exactly one restore event, and passes the 485-test full suite. Operator restore acceptance remains.
- [ ] `AVL-P0-033`: implementation and automated proof are landed. Disabled companies now remove inventory from sidebar, menus, palette, shortcut help, reports, dashboard, voucher item loading, and keyboard routing; `AppRouter` rejects method and direct-property deep links, invalidates stale state on company/toggle changes, and inventory, BOM, order, item-invoice, and stock-report service boundaries fail closed. The 485-test full suite passes. Manual accountant capability-toggle acceptance remains.
- [x] Core double-entry accounting uses `Int64` paise, typed errors, checked arithmetic, and deterministic date handling.
- [x] Financial-year creation, lock/unlock, close, reopen, carry-forward, and overlap rejection are implemented.
- [x] Audit records are HMAC-chain protected and company open fails closed on tampering.
- [ ] `AVL-P0-034`: implementation and automated proof are landed. V023/V025 provide dedicated actions for shipped mutations, including compound cheque bounce/re-presentation snapshots; export events publish only after successful file save and failed audit publication removes the artifact. Update paths preserve before/after data, required reasons are retained, and the unavailable repair workflow remains hidden under `AVL-P1-039`. Mutation-contract, chain-preservation, rollback, snapshot, app-flow, export, 50-cycle backup/restore, 494-test full-suite, and rule-audit proof pass. Representative accountant audit-diff acceptance remains.
- [ ] `AVL-P0-037`: implementation and automated proof are landed. The ancestry-aware `AccountEligibilityPolicy` drives voucher batch/single validation, pickers, item invoices, orders, banking, payroll, cash/bank report selection, and the shipped bank-statement import. V024 profiles, full ancestry, the core voucher-field context matrix, retained invalid values, regrouping, and Alt+C account creation all use the same reloaded policy. The 498-test full suite, focused import/new-master proof, and rule audit pass. No account-master importer ships before Phase 8; accountant picker and retained-selection acceptance remains.
- [ ] `AVL-P0-020`: implementation and automated proof are landed for Return/add-line, Command-Return post/save, Tab/Shift-Tab native traversal, Escape, validation focus, nested sheet capture, native text precedence, and duplicate-submit prevention. The 498-test full suite passes. Manual accountant first/middle/last/insert/delete/error traversal plus bundled keyboard and VoiceOver acceptance remains; the broader action-generated alias engine is `AVL-P1-044`.
- [x] SQLite foreign keys, WAL, statement lifecycle cleanup, busy timeout, schema migration, and integrity checks are in place.
- [x] Company ownership and fiscal-lock rules are enforced at service and database-trigger layers.

## 2. Core bookkeeping and reporting — implemented; release acceptance pending

- [x] Chart of accounts, account groups, ledger masters, opening balances, GST party details, and bill-wise fields.
- [x] Account-group create, update, and seed-import paths reject cycles, foreign-company parents, and nature-incompatible hierarchy.
- [x] Voucher posting, edit, reverse, cancel, draft autosave/recovery, templates, and gap-free numbering.
- [x] Tally-style single-entry entry for Contra, Payment, and Receipt vouchers.
- [x] Explicit item-invoice entry for Sales/Purchase derives reviewable GST/CESS ledger lines from user-entered quantity/rate plus stored item/place-of-supply metadata, then posts accounting, item lines, and stock movements atomically on save.
- [x] Cash, bank, journal, sales, purchase, receipt, payment, credit-note, debit-note, opening, and payroll voucher types.
- [x] Trial Balance, Profit & Loss, Balance Sheet, ledger, Day Book, cash flow, cash/bank books, outstanding, GST, stock valuation, stock register, and stock-ageing reports.
- [x] Report reconciliation tests and trial-balance netting.
- [x] B2B GST PDF invoice output with HSN/SAC, place of supply, CGST/SGST/IGST/CESS, and inventory-linked detail.
- [x] Offline GSTR summary and invoice-wise CSV export.

## 3. Inventory, banking, and operational workflows — implemented or active

- [x] Inventory item masters, units, exact alternate-UOM quantities, FIFO/weighted-average valuation, and backdated recalculation.
- [x] Bill-wise allocation engine and outstanding calculation.
- [x] Sales/purchase order services and basic UI.
- [x] Cheque register, bounce, and re-presentation UI.
- [x] BOM recipe persistence, circular-BOM rejection, list/edit UI, and repository/service coverage (recipe setup only; not manufacturing execution).
- [x] Hardened BOM recipe setup: exact quantities, explicit create-versus-update, duplicate-component guards, atomic cycle validation, audit records, and archive/load error handling are implemented and covered. Manufacturing execution remains a later workflow.
- [x] Bank statement CSV import and baseline reconciliation flow.
- [x] Payroll employees, salary entries, salary vouchers, and payroll register.
- [ ] `AVL-P0-033`: inventory-disabled Reports now hide stock selections and reject stale/deep-linked stock report selections. The full sidebar/menu/palette/search/shortcut/sheet/service matrix, current full-suite proof, and accountant acceptance remain.
- [ ] `AVL-P0-035`: implementation and automated proof are landed. Production UI exposes only manual ledger-voucher inventory linkage; legacy automatic values remain decodable but are rejected by every `CompanyService` update path, emit no incomplete prompt or hidden stock consequences across post/edit/cancel/reverse, and default to manual in new/demo flows. Focused mode tests, the 485-test full suite, and rule audit pass; accountant acceptance remains.
- [ ] `AVL-P0-020`: enforce one voucher keyboard contract—plain Return advances/adds a line, Command-Return posts/saves, Tab/Shift-Tab traverse predictably, and create/edit/help mappings agree.
- [x] Resolved the active voucher-entry blockers: type-checkable UI composition, single-entry duplicate/recovery, account-creation eligibility plus domain invariants, robust `Alt+C`, and accessible narration recall.
- [x] Completed the active voucher/BOM implementation worktree and its targeted regression coverage.
- [ ] Complete the final-worktree full regression and release proof suite; see Section 0 for the specific blocked reruns.
- [ ] Confirm the new voucher account-creation, narration-recall, item-mode, and BOM flows manually in the bundled app.

## 4. v1.1 release gate — do next, in this order

1. [ ] Finish current-worktree automated proof. Targeted audit/voucher tests, the focused backup-cleanup test, and all opt-in performance tests passed on 2026-07-15; the normal full-suite restart, `make rule-audit`, `make rc-local`, same-machine benchmark checks, `make launch-smoke`, and GUI launch must still be completed after the final test-harness fix. Record the commit/worktree identity and all skipped tests. The current launch-smoke target validates/self-tests the bundle; separately launch the GUI with `open dist/Avelo.app` in a normal session.
2. [ ] Run accountant acceptance for invoice rounding, bill settlement, cheque bounce/re-presentation, BOM handling, valuation, backdated stock corrections, trial balance, cancellation, and year close/reopen.
3. [ ] Run operator acceptance for company create/restore, corrupt database recovery, iCloud-exclusion policy, migrations, App Nap/sleep behavior, and statement-resource cleanup.
4. [ ] Run keyboard-entry acceptance for Tab, Shift-Tab, Return, validation failures, line insertion, and Tally shortcut routing.
5. [ ] Run accessibility acceptance for VoiceOver names/values/grouping, visible focus, keyboard-only completion, contrast, non-color-only status, resizing, empty states, and error recovery on shipped paths.
6. [ ] Run visual/document acceptance for B2B invoice PDF layout, GST breakdown, printing totals, light/dark appearance, resizing, and company switching.
7. [ ] Select and document the public distribution path. The current bundle is ad-hoc signed and therefore only a local RC; public release requires Developer ID signing plus notarization (or a separately approved Mac App Store path), hardened-runtime/entitlement review, and a clean-Mac install/launch test.
8. [x] Bundle metadata is aligned to v1.1 build 3 through `ReleaseVersion.env`; assembly, validation, changelog, and release documents use the same declared source.
9. [ ] Update `Docs/Avelo_Release_Board.md` and `Docs/Avelo_Execution_Checklist.md` with current evidence only.
10. [ ] Cut the v1.1 changelog, build the final artifact, verify installation/launch, and tag only when every P0 item and the chosen distribution gate are accepted.

## 5. Daily Tally workflow parity — after v1.1

1. [ ] Finish bill-wise allocation UI in Payment, Receipt, Sales, and Purchase editors; add bill-wise outstanding and ageing screens.
2. [ ] Add simple and advanced overdue-interest policies with auditable posting rules.
3. [ ] Finish order fulfilment, partial fulfilment, rejection, and pending-order reporting.
4. [ ] Turn BOM definitions into manufacturing/production vouchers with inventory consumption and finished-goods output.
5. [ ] Add cost-centre allocation on voucher lines, then cost categories and budget-versus-actual reporting.
6. [ ] Add voucher classes for deterministic ledger, tax, and freight expansion.
7. [ ] Add comparative report columns, report configuration, drill-down/return-context, and editable Day Book correction flow.
8. [ ] Complete keyboard parity: Alt+C master creation with focus return, Ctrl+V mode toggle, Alt+2 duplicate, Ctrl+R narration recall, Ctrl+I insert, PgUp/PgDn navigation, and a context-safe shortcut engine.
9. [ ] Add multi-window company/editor isolation, optimistic conflict handling, and undo/redo model-view resynchronisation.

## 6. Inventory and business controls — after daily workflows

1. [ ] Add godowns, stock transfers, in-transit ownership, and godown-wise reports.
2. [ ] Add batches, expiry enforcement, override audit, and orphaned-batch repair.
3. [ ] Define negative-stock policy and deterministic later-receipt adjustment.
4. [ ] Add by-product and scrap allocation to manufacturing workflows.
5. [ ] Add stock categories, reorder-level reporting/alerts, and POS invoicing where the target business needs retail checkout.
6. [ ] Improve bank reconciliation with durable match/unmatch/clear state, import fingerprints, idempotency, MT940/CAMT.053 import, and explainable matching.

## 7. Offline compliance and payroll — after inventory controls

1. [ ] Export GSTR-1/1A/IFF and GSTR-3B in portal-compatible file formats, with reconciliation evidence.
2. [ ] Import downloaded GSTR-2B files and implement ITC/IMS accept, reject, and pending reconciliation locally.
3. [ ] Add B2C, export, credit-note, debit-note, and RCM invoice documents.
4. [ ] Generate offline e-way bill preparation files for manual portal upload.
5. [ ] Implement TDS/TCS workflows and filing exports.
6. [ ] Add PF, ESI, Professional Tax, effective-date rate handling, attendance, pay heads, and payroll rounding.
7. [ ] Produce Form 16, 24Q/26Q, 27Q, and 27EQ exports with schema validation.
8. [ ] Add GSTR-9/9C reconciliation and traceable difference reporting.
- [x] Keep portal upload APIs, e-invoice IRN generation, and signed government QR issuance out of scope while the offline-only rule stands.

## 8. Migration, interchange, and scale — later releases

1. [ ] Build an offline Tally importer with dry-run mapping, resumability, duplicate control, reconciliation report, and rollback-safe staging.
2. [ ] Add multi-currency books, rates, realised/unrealised forex, and revaluation journals.
3. [ ] Improve CSV/TSV import handling for BOMs, embedded delimiters, nested quotes, and multiline fields.
4. [ ] Add batch printing, print profiles, cheque templates, regional-script PDF font coverage, and XLSX fidelity.
5. [ ] Add repair/reindex with dry run, mandatory backup, progress, verification, and audit trail.
6. [ ] Add WAL checkpoint policy, Time Machine consistency checks, filesystem placement warnings, and longer soak/crash tests.
7. [ ] Evaluate document signing, email delivery, legacy export formats, and hardware-independent licensing only after their offline/security implications are explicitly approved.

## 9. Completion rule for every unchecked item

- [ ] Define the user workflow and failure behavior before implementation.
- [ ] Add forward-only migration and extend ownership/fiscal-lock/audit protections if persistent data changes.
- [ ] Add service, repository, restore, company-isolation, and regression tests appropriate to the feature.
- [ ] Run the full release proof set.
- [ ] Record every applicable accountant, operator, keyboard, accessibility, visual/document, and distribution acceptance before marking the feature release-ready.
