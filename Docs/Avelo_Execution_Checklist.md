# AVELO Master Execution Checklist

Snapshot: 2026-07-15

## Summary

This file is the remaining-work execution queue. It tracks only unfinished `AVL-*` backlog items from `Docs/Avelo_Release_Board.md`, grouped into dependency-ordered waves through P2.

The dependency order is governed by `Docs/Avelo_Master_Product_Execution_Plan.md`: v1.1 correctness, account eligibility, shared interaction, masters, voucher workstation, inventory/orders/banking, reports/charts, documents/exports, compliance/payroll, reliability/import/scale, advanced accounting, then the offline Avelo Extension Language.

Rules:

- `Docs/Avelo_Release_Board.md` remains the canonical source of truth for backlog scope, dependencies, and proof-of-done.
- Historical `RB-*` work is evidence only and does not appear in the active queue here.
- Human Phase 0 results are recorded only in `Docs/Avelo_Phase0_Manual_Acceptance.md`; agent QA logs and automated tests cannot mark those gates passed.
- An item stays in this checklist until its implementation, automated proof, relevant full-suite proof, and manual accountant acceptance are all recorded.
- Release verdict remains `NOT READY` while any `AVL-P0-*` row is still open on the board.

Execution states:

- `Implementation remaining` — code, schema, workflow, or UI behavior is still missing.
- `Proof remaining` — implementation has landed substantially, but targeted/full-suite/manual proof is still incomplete.
- `Manual acceptance remaining` — automated proof is complete enough to stop coding, but accountant QA is still pending.
- `Policy excluded` — intentionally excluded by a non-negotiable rule; prove it is absent rather than implement it.
- `Closed` — implementation, current automated proof, applicable human acceptance, and evidence metadata are complete.

Current-worktree reset: active source, migration, test, documentation, and bundle changes mean earlier green logs are historical only. Every affected row is at least `Proof remaining` until the current worktree and one exact artifact complete the supported gate.

Evidence template required before striking an item:

- `Implemented`: code path and invariant now exist.
- `Automated proof`: exact targeted test commands.
- `Manual proof`: accountant scenario, steps, and expected output/result.
- `Residual risk`: blank if closed; explicit if reopened or partially blocked.
- `Evidence identity`: date/time/timezone, commit, worktree diff identity, macOS/Xcode/Swift, machine, schema/fixture, skipped tests, artifact version/build/SHA-256/signing identity, and owner.

## Release gate policy

### P0 gate

Before calling Avelo release-ready:

- no `AVL-P0-*` remains open on the board
- every P0 item has targeted automated proof
- `make rule-audit`, a warnings-as-errors release build, `make test`, `make rc-local`, applicable benchmarks, bundle self-test, and separate GUI launch proof are recorded
- every P0 item has a written manual accountant acceptance script and completed result
- operator, keyboard, accessibility, visual/PDF, and distribution acceptance is complete where applicable

### P1 gate

Before broad rollout:

- no accountant-critical workflow still relies on `featureUnavailable`
- legal and compliance exports validate against fixtures
- supported Tally-replacement daily flows are keyboard-complete

### P2 gate

P2 remains real work but must not block the P0 release verdict unless a P0 or P1 proof explicitly depends on it.

## Wave P0-A — foundational proof closure

Close proof gaps first for already-advanced items that unblock later work.

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P0-012 | Manual acceptance remaining | None | Execute the accountant verification script for tamper rejection on company open/repair paths against the shipped keyed audit chain. | Accountant tamper-rejection acceptance is still pending; automated proof is complete on `AuditTamperEvidenceTests` (mutated/deleted/inserted/reordered rows and whole-chain rewrite all detected), `DatabaseManagerFileResolutionTests`, `AuditRepositoryTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-011 | Manual acceptance remaining | None | Execute accountant overflow acceptance scenarios for voucher, payroll, reports, and banking against the shipped `CheckedMath` fail-closed arithmetic. | Accountant overflow acceptance is still pending; automated proof is complete on `VoucherDraftTests` (`testCheckedTotalsThrowOnOverflow`, `testOverflowingDraftFailsClosedForNonThrowingHelpers`), `AccountTreeReconciliationTests`, `Phase6MathRoundingTests`, `CurrencyTests`, and full `swift test`. |
| AVL-P0-025 | Manual acceptance remaining | AVL-P0-023 behavior must stay consistent | Execute the accountant script for overlapping-FY rejection and deterministic date resolution against the shipped overlap guard. | Accountant overlap-rejection acceptance is still pending; automated proof is complete on `FinancialYearServiceTests` (`testCreateRejectsOverlappingFinancialYear`, `testFinancialYearLookupFailsClosedWhenCorruptYearsOverlap`) and full `swift test`. |
| AVL-P0-026 | Manual acceptance remaining | AVL-P0-025 | Execute the accountant script for voucher, stock, payroll, banking, and opening-balance lock rejection against the shipped fiscal-lock triggers. | Accountant lock-rejection acceptance is still pending; automated proof is complete on `FiscalLockEnforcementTests` (7 tests spanning inventory, bank statements, payroll, opening balances, and voucher updates at both service and trigger layers) and full `swift test`. |
| AVL-P0-030 | Manual acceptance remaining | None | Execute the accountant script for company-isolation rejection at service/UI level against the shipped ownership guards. | Accountant company-isolation acceptance is still pending; automated proof is complete on `CompanyIsolationTests` (7 tests spanning vouchers, accounts, financial years, ledger lines, stock, payroll, and bank import at both service and trigger layers) and full `swift test`. |
| AVL-P0-027 | Manual acceptance remaining | None | Execute the accountant corruption-handling script for fail-closed open/read behavior against the shipped strict-decoding path. | Accountant corruption-handling acceptance is still pending; automated proof is complete on `SQLiteDatabaseTests` (`testOptionalDateReturnsNilForMalformedValue`, `testTimestampThrowsForMalformedValue`, `testOpeningCorruptDatabaseBytesFailsClosedInsteadOfFallingBackToSchemaZero`) and full `swift test`. |
| AVL-P0-002 | Manual acceptance remaining | None | Execute the accountant script for contiguous numbering under failure/retry against the shipped atomic sequence reservation. | Accountant contiguous-numbering acceptance is still pending; automated proof is complete on `VoucherServiceTests` (`testFailedPostDoesNotConsumeVoucherNumber`, `testFailedBatchChunkDoesNotAdvanceVoucherNumbers`, `testConcurrentPostsAllocateGapFreeSequentialVoucherNumbers`, `testCancelledVoucherNumberIsNotReusedByNextPost`, `testPostBatchRollsBackOnlyCurrentChunkOnFailure`) and full `swift test`. |

## Wave P0-B — remaining accounting and fiscal blockers

Execute in this order after Wave P0-A is green enough to avoid rework.

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P0-005 | Manual acceptance remaining | AVL-P0-025 and AVL-P0-026 | Execute the accountant year-close acceptance script against the shipped exact-once carry-forward, reopen cleanup, and idempotent close behavior. | Accountant year-close acceptance is still pending; automated proof is complete on `FinancialYearCloseCarryForwardTests`, `FinancialYearServiceTests`, `ReportBehaviorTests`, `AccountTreeReconciliationTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-006 | Manual acceptance remaining | AVL-P0-026 | Execute the accountant locked-period correction script against the shipped read-only locked-FY voucher workflow and linked reversal path into an open FY. | Accountant locked-period correction acceptance is still pending; automated proof is complete on `VouchersViewTests`, `VoucherServiceTests`, `FiscalLockEnforcementTests`, and full `swift test`. |
| AVL-P0-007 | Manual acceptance remaining | AVL-P0-002 | Execute the keyboard-entry acceptance script against the shipped one-shot submit guard for voucher posting. | Accountant keyboard-entry acceptance is still pending; automated proof is complete on `VouchersViewTests`, `VoucherServiceTests`, `AccountantRCFlowTests`, and full `swift test`. |
| AVL-P0-003 | Manual acceptance remaining | None | Execute the accountant outstanding-reconciliation script against the shipped bill-allocation engine, voucher persistence, reversal mirroring, and restore-safe remap behavior. | Accountant bill-wise outstanding acceptance is still pending; automated proof is complete on `VoucherServiceTests`, `ReportBehaviorTests`, `RestoreServiceTests`, `AccountantRCFlowTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-004 | Manual acceptance remaining | AVL-P0-003 | Execute the accountant bounced-cheque script against the shipped cheque persistence, linked reversal, re-presentation, restore remap, and edit round-trip behavior. | Accountant cheque reversal acceptance is still pending; automated proof is complete on `VoucherServiceTests`, `RestoreServiceTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-009 | Manual acceptance remaining | AVL-P0-011 | Execute the manufacturing validation script against the shipped BOM persistence path and direct/indirect cycle rejection before save/load. | Manufacturing validation acceptance is still pending; automated proof is complete on `BOMServiceTests`, `RestoreServiceTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-008 | Manual acceptance remaining | AVL-P0-011 | Execute the accountant unit-conversion script against the shipped rational alternate-UOM persistence and conversion paths across stock posting and valuation. | Accountant unit-conversion acceptance is still pending; automated proof is complete on `InventoryServiceTests` and full `swift test`. |
| AVL-P0-010 | Manual acceptance remaining | AVL-P0-008 and AVL-P0-011 | Execute the accountant valuation-verification script against the shipped FIFO/weighted-average layer replay, authoritative stock-out costing, residual paise handling, and stock-valuation reporting paths. | Accountant valuation acceptance is still pending; automated proof is complete on `InventoryServiceTests`, `ReportBehaviorTests`, and full `swift test`. |
| AVL-P0-024 | Manual acceptance remaining | AVL-P0-011 | Execute the accountant trial-balance verification script against the shipped per-account netting, seeded/live SQL reconciliation, and later-FY carry-forward report paths. | Accountant trial-balance acceptance is still pending; automated proof is complete on `TrialBalanceNettingTests`, `AccountTreeReconciliationTests`, `ReportBehaviorTests`, and full `swift test`. |
| AVL-P0-019 | Manual acceptance remaining | AVL-P0-010 | Execute the accountant backdated-stock correction script against the shipped downstream recalculation and publication behavior for insert, reversal, and replacement flows. | Accountant backdated-stock acceptance is still pending; automated proof is complete on `InventoryServiceTests` and full `swift test`. |
| AVL-P0-001 | Manual acceptance remaining | None | Execute the accountant invoice-rounding script against the shipped GST round-off normalization, edit recomputation, and seeded/migrated `ROUND_OFF` ledger behavior. | Accountant invoice-rounding acceptance is still pending; automated proof is complete on `VoucherServiceTests`, `SchemaDriftTests`, and full `swift test`. |
| AVL-P0-032 | Manual acceptance remaining | AVL-P0-002 and AVL-P0-012 | Execute the accountant voucher-cancel acceptance script against the shipped status/reason/timestamp persistence, linked reversal, number preservation, and audit-history behavior. | Accountant voucher-cancel acceptance is still pending; automated proof is complete on `VoucherServiceTests`, `AuditCoverageTests`, and full `swift test`. |

Exit criteria for this wave:

- every ledger-impacting path has golden fixtures
- every workflow has an explicit accountant acceptance script
- no bill-wise stub is still treated as acceptable readiness evidence; core BOM cycle-safe persistence and cheque bounce/re-presentation are ship-path proven, while broader manufacturing and cheque-adjacent workflows stay open until their remaining backlog items land

## Wave P0-C — storage, UI, and legal blockers

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P0-028 | Manual acceptance remaining | None | Execute the accountant company-picker preservation script against the shipped collision-safe registry insert/update path. | Accountant company-picker preservation acceptance is still pending; automated proof is complete on `RegistryRepositoryTests`, `DatabaseManagerFileResolutionTests`, and full `swift test`. |
| AVL-P0-031 | Manual acceptance remaining | None | Execute the operator recovery script against the shipped throwing schema-version read path for unreadable/corrupt company databases and restore inputs. | Operator recovery acceptance is still pending; automated proof is complete on `SQLiteDatabaseTests`, `DatabaseManagerFileResolutionTests`, `BankReconciliationServiceTests`, and full `swift test`. |
| AVL-P0-029 | Manual acceptance remaining | AVL-P0-028 and AVL-P0-031 | Execute the operator company-create rollback script against the shipped compensating cleanup path and honored `seedDefaults` behavior. | Operator company-create rollback acceptance is still pending; automated proof is complete on `CompanyServiceCreationTests`, `AppEnvironmentFlowTests`, `RestoreServiceTests`, and full `swift test`. |
| AVL-P0-013 | Manual acceptance remaining | None | Execute the operator storage-policy script against the shipped backup-exclusion metadata on app support roots, registry, company databases, restore staging, and restored company files. | Clean-device/manual storage verification is still pending; automated proof is complete on `DatabaseManagerFileResolutionTests`, `RestoreServiceTests`, and full `swift test`. |
| AVL-P0-014 | Manual acceptance remaining | None | Execute sleep/App Nap QA against the shipped `ProcessInfo` activity hold/release around migrations, restore, backup, repair, and recalculation. | Sleep/App Nap manual verification is still pending; automated proof is complete on `LongOperationActivity` call sites (`MigrationRunner`, `BackupService`, `RestoreService`, `InventoryService`) and full `swift test`. |
| AVL-P0-015 | Manual acceptance remaining | AVL-P0-031 | Execute operator migration acceptance against the shipped off-main-thread `DatabaseManager` actor with progress reporting. | Large-migration operator acceptance is still pending; automated proof is complete on migration-progress tests and full `swift test`. |
| AVL-P0-016 | Manual acceptance remaining | None | Execute accountant shell-flow acceptance against the shipped single-source `AppEnvironment.companyContext`/router state. | Company-switch/window/sheet accountant acceptance is still pending; automated proof is complete on `AppEnvironmentFlowTests` and full `swift test`. |
| AVL-P0-017 | Manual acceptance remaining | None | Execute operational leak-free acceptance against the shipped `sqlite3_finalize`/reset/clear coverage on every statement lifecycle path. | Operational leak-free acceptance is still pending; automated proof is complete on `SQLiteDatabaseTests` and full `swift test`. |
| AVL-P0-018 | Manual acceptance remaining | None | Execute accountant draft-recovery acceptance against the shipped autosave/crash-recovery flow (kill/relaunch, single-entry-mode `accountLedgerId` restored via `MigrationV021`). | Accountant draft-recovery acceptance is still pending; automated proof is complete on `VoucherDraftTests`, `VoucherDraftRepositoryTests`, and full `swift test`. |
| AVL-P0-020 | Manual acceptance remaining | None | New/Edit voucher editors use Return to advance/add, Command-Return to post/save through one-shot submission, native Tab/Shift-Tab traversal, Escape cancellation, validation-error focus, native text-editor precedence, and depth-safe sheet shortcut capture. Physical function-key translation is centralized in `KeyboardShortcuts`. | Focus/add-line/validation/request, shortcut-map, nested-capture, text-precedence, and one-shot tests plus the 498-test full suite pass. Accountant must still execute first/middle/last/insert/delete/error traversal and bundled keyboard/VoiceOver acceptance; the broader generated action registry remains `AVL-P1-044`. |
| AVL-P0-021 | Manual acceptance remaining | None | Execute accountant locale-entry acceptance against the shipped `Currency.parseRupeeInput` locale-aware decimal parsing and paise storage. | Accountant locale-entry acceptance is still pending; automated proof is complete on `CurrencyTests` and full `swift test`. |
| AVL-P0-023 | Manual acceptance remaining | None | Execute accountant FY/GST period acceptance against the shipped fixed-UTC `IndianFinancialYear` calendar semantics. | Accountant FY/GST period acceptance is still pending; automated proof is complete on `IndianFinancialYearTests`, `FinancialYearServiceTests`, `FinancialYearCloseCarryForwardTests`, and full `swift test`. |
| AVL-P0-022 | Manual acceptance remaining | None | GST-compliant PDF/invoice output for registered-party (B2B) Sales/Purchase vouchers: mandatory fields, CGST/SGST/IGST/CESS breakdown, HSN/SAC, place of supply, inventory-linked stock detail. B2C/export/notes/RCM deferred to follow-on tickets; signed QR/e-invoice IRN is permanently out of scope (blocked by R-1, offline-only) rather than gated on `AVL-P1-008`. | Implementation and automated proof are landed (`InvoicePDFServiceTests`, `GSTServiceTests`, `GSTStateCodeTests`, `InventoryServiceTests`); remains open only until accountant B2B tax-invoice acceptance is executed and recorded. |
| AVL-P0-033 | Manual acceptance remaining | None | Implementation is landed across sidebar, menus, palette, shortcut help, reports, dashboard, voucher item loading, keyboard routing, direct router/deep-link authorization, stale-state invalidation, and inventory/BOM/order/item-invoice/report service boundaries. | Automated enabled/disabled router, keyboard, report, item-invoice, service, and company-switch checks plus the 485-test full suite pass; accountant toggles the capability across companies and confirms no stale route or data loss. |
| AVL-P0-034 | Manual acceptance remaining | AVL-P0-012 | Implementation is landed through V023/V025: every shipped mutation has an executable contract, cheque bounce/re-presentation use dedicated compound snapshots, saved-file exports audit after publication with compensating deletion, and unavailable repair stays hidden under AVL-P1-039. | Chain-preservation, exactly-one-event, rollback, snapshot, app-flow, export, 50-cycle backup/restore, 494-test full-suite, and rule-audit proof pass; representative accountant audit-diff acceptance remains. |
| AVL-P0-035 | Manual acceptance remaining | AVL-P0-033 and AVL-P0-034 | Production UI exposes only manual linkage; both legacy automatic modes are rejected by direct and general company updates and produce no prompt or hidden stock consequences across post/edit/reverse/cancel. | Focused mode tests, the 485-test full suite, and rule audit pass; accountant confirms unsupported controls are absent and manual/item-invoice workflows remain explicit. |
| AVL-P0-036 | Manual acceptance remaining | AVL-P0-030 and AVL-P0-031 | Implementation and automated proof are landed: `avelo_voucher_item_lines` and `avelo_party_profiles` remap, drafts are discarded, and real V14–V22 schemas upgrade with FY-opening, bill, cheque, BOM, voucher, ledger, stock, item-line, and profile fixtures. A dynamic scan proves every current `company_id` table is free of the source identity. | V14–V22 migration/remap, foreign-key, exactly-one-audit-event, focused restore, and 485-test full-suite proof pass; operator performs cross-machine recovery-key restore and confirms the discard notice and reconciled books. |
| AVL-P0-037 | Manual acceptance remaining | AVL-P0-020, AVL-P0-033, AVL-P0-034 | V024 dual-role party profiles feed the shared policy in voucher batch/single validation, pickers, item invoices, orders, banking, payroll, reports, and the shipped bank-statement import, and restore remaps them. Regrouping and Alt+C account creation reload the authoritative account/group/profile context immediately. | The core voucher-field context matrix, ancestry, cash/bank, sales/purchase, dual-role, inactive/foreign, retained-selection, bank-import rejection, regrouping, new-account, migration/restore, 498-test full-suite, and rule-audit proof pass. Account-master import remains a Phase 8 Tally-importer workflow; accountant picker and retained-invalid-selection acceptance remains. |

## Wave P1-A — accountant workflow core

Daily bookkeeping and Tally-replacement core before filing breadth.

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P1-028 | Implementation remaining | AVL-P0-010 | Rebuild bank reconciliation to match selected bank ledger legs, signed direction, persisted matches, import fingerprints, and idempotency. | Match/clear/unmatch/import-duplication fixtures, full `swift test`, and accountant bank-reco acceptance. |
| AVL-P1-029 | Implementation remaining | AVL-P0-010 | Build consumable stock-ageing layers that reconcile buckets to on-hand quantity and value. | FIFO-ageing fixtures, full `swift test`, and accountant stock-ageing acceptance. |
| AVL-P1-030 | Implementation remaining | AVL-P0-030 | Block account-group cycles, cross-company parents, and nature conflicts on create/import/update. | Hierarchy-cycle fixtures, full `swift test`, and accountant chart-integrity acceptance. |
| AVL-P1-031 | Implementation remaining | None | Add checksummed recovery keys with typo-specific errors and versioning. | Single-character mutation fixtures, full `swift test`, and operator recovery-key acceptance. |
| AVL-P1-033 | Implementation remaining | AVL-P0-009 and AVL-P0-010 | Replace BOM, bill allocation, cheque, TDS/TCS, and cost-centre readiness stubs with real guarded workflows. | No-`featureUnavailable` shipped-path proof, full `swift test`, and accountant workflow acceptance. |
| AVL-P1-010 | Implementation remaining | AVL-P0-030 | Add cost-centre per-line allocation with report reconciliation and keyboard selection context. | Split-allocation fixtures, full `swift test`, and accountant allocation acceptance. |
| AVL-P1-011 | Implementation remaining | AVL-P1-010 | Add cost categories for parallel allocation dimensions. | Parallel-dimension fixtures, full `swift test`, and accountant category acceptance. |
| AVL-P1-034 | Implementation remaining | AVL-P1-010 | Implement Voucher Classes for deterministic ledger/tax/freight expansion. | Class-version fixtures, full `swift test`, and accountant fast-entry acceptance. |
| AVL-P1-035 | Implementation remaining | AVL-P0-003 | Implement simple/advanced ledger interest policies with posting rules. | Interest-schedule fixtures, full `swift test`, and accountant overdue-interest acceptance. |
| AVL-P1-036 | Implementation remaining | None | Add comparative report columns and period-selection model. | Multi-period reconciliation fixtures, full `swift test`, and accountant comparative-report acceptance. |
| AVL-P1-037 | Implementation remaining | AVL-P0-032 | Build editable universal Day Book with inline drill-down, cancel, and date navigation. | Browse-to-correction fixtures, full `swift test`, and accountant Day Book acceptance. |
| AVL-P1-038 | Implementation remaining | AVL-P0-020 and AVL-P1-010 | Build continuous multi-account voucher entry with inline cost allocation and no submodal dependency. | Complex keyboard-only voucher fixtures, full `swift test`, and accountant continuous-entry acceptance. |
| AVL-P1-040 | Implementation remaining | AVL-P0-022 baseline invoice behavior | Implement orders and logistics vouchers with fulfillment linkage. | Partial fulfillment/rejection/count fixtures, full `swift test`, and accountant stock-flow acceptance. |
| AVL-P1-041 | Implementation remaining | AVL-P0-032 | Implement voucher/invoice mode split and post-dated voucher lifecycle distinct from cheque state. | Mode/post-date lifecycle fixtures, full `swift test`, and accountant post-dated acceptance. |
| AVL-P1-044 | Implementation remaining | AVL-P0-020 | Registry core has landed (`Avelo/Core/Actions/`): `AppActionID`/context/availability/effect plus a catalog for Accounts, Vouchers, Trial Balance, and Day Book, with menus, both toolbars, command palette, shortcut help, and keyboard dispatch all reading from it. Remaining: context-awareness itself (availability gates on selection and voucher type only — not on workspace, capability, fiscal lock, or input focus), Day Book/Trial Balance row actions in `ReportsBody+Activity.swift` and `ReportsBody+FinancialStatements.swift` (deferred to the Phase 1 report explorer), and text-entry precedence. | Full shortcut matrix, keyboard-collision and text-precedence proof, and accountant keyboard-flow acceptance. `AppActionRegistryTests` (11 tests) and the 509-test full suite pass, but cover only the availability subset that exists today. |

## Wave P1-B — compliance and filing

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P1-004 | Implementation remaining | None | Implement PF, ESI, Professional Tax, and payroll effective-rate rounding. | Golden payroll fixtures, full `swift test`, and payroll-operator acceptance. |
| AVL-P1-005 | Implementation remaining | None | Build Form 16 and 24Q/26Q exports with schema validation. | Export-schema fixtures, full `swift test`, and payroll filing acceptance. |
| AVL-P1-006 | Implementation remaining | AVL-P1-005 | Add 27Q/27EQ and correction/export workflows. | Validation fixtures, full `swift test`, and filing acceptance. |
| AVL-P1-008 | Policy excluded | None | Keep direct IRN issuance, portal cancellation, and government-signed QR retrieval out of Avelo while R-1 requires zero network access. Scope offline import/retention/printing separately if requested. | Network/routing/dependency scan proves no portal path exists; product copy does not imply IRN or government-signed QR issuance. |
| AVL-P1-002 | Implementation remaining | AVL-P0-022 baseline document path | Implement RCM self-invoicing and linked postings. | Inward-supply fixtures, full `swift test`, and accountant RCM acceptance. |
| AVL-P1-007 | Implementation remaining | AVL-P0-022 baseline document path | Build GSTR-1/1A/IFF, 3B, 2B, and IMS reconciliation with accept/reject/pending states. | Portal-format fixtures, full `swift test`, and GST-filing acceptance. |
| AVL-P1-016 | Implementation remaining | AVL-P1-007 | Implement debit/credit-note linkage across GST periods. | Cross-period note fixtures, full `swift test`, and accountant amendment acceptance. |
| AVL-P1-001 | Implementation remaining | None | Implement GSTR-9/9C reconciliation with traceable difference reporting. | Annual reconciliation fixtures, full `swift test`, and accountant annual-return acceptance. |
| AVL-P1-003 | Implementation remaining | None | Implement e-way bill Part-B lifecycle with audit visibility. | Transition/state fixtures, full `swift test`, and operator logistics acceptance. |

## Wave P1-C — reliability, printing, signing, interchange, and Tally flow

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P1-017 | Implementation remaining | AVL-P0-016 | Add multi-window company/editor isolation and restoration. | Two-window stress fixtures, full `swift test`, and operator multi-window acceptance. |
| AVL-P1-018 | Implementation remaining | AVL-P0-030 | Add optimistic locking/conflict handling for concurrent edits. | Stale-write conflict fixtures, full `swift test`, and operator concurrent-edit acceptance. |
| AVL-P1-019 | Implementation remaining | AVL-P0-013 | Detect symlinks, external/network drives, and unsupported filesystems. | File-placement matrix, full `swift test`, and operator storage-policy acceptance. |
| AVL-P1-020 | Implementation remaining | AVL-P0-017 | Add WAL checkpoint management with bounded growth and surfaced failures. | Long-session/crash fixtures, full `swift test`, and operator durability acceptance. |
| AVL-P1-021 | Implementation remaining | AVL-P0-013 | Add Time Machine registry/company consistency checks and guidance. | Snapshot-skew fixtures, full `swift test`, and operator recovery acceptance. |
| AVL-P1-022 | Implementation remaining | None | Strip CSV BOM safely. | UTF BOM fixtures, full `swift test`, and import acceptance. |
| AVL-P1-023 | Implementation remaining | None | Support nested quotes and embedded delimiters in CSV imports. | RFC-style CSV fixtures, full `swift test`, and import acceptance. |
| AVL-P1-024 | Implementation remaining | None | Support quoted/embedded line breaks in TSV. | Multiline TSV fixtures, full `swift test`, and import acceptance. |
| AVL-P1-025 | Implementation remaining | AVL-P0-016 | Fix undo/redo model-view resync in voucher grids. | Undo/redo stress fixtures, full `swift test`, and keyboard-edit acceptance. |
| AVL-P1-026 | Implementation remaining | AVL-P0-020 | Add mid-voucher master creation flow with focus return and audit. | Alt+C keyboard fixtures, full `swift test`, and accountant draft-preservation acceptance. |
| AVL-P1-027 | Implementation remaining | None | Build Tally importer with dry run, mapping, resumability, and reconciliation report. | Representative import fixtures, full `swift test`, and accountant import acceptance. |
| AVL-P1-032 | Implementation remaining | AVL-P0-012 | Complete audit coverage for FY unlocks, bank ops, inventory orders, repair, exports, printing, signing, and email. | Mutation-inventory fixtures, full `swift test`, and audit review acceptance. |
| AVL-P1-039 | Implementation remaining | AVL-P0-012 and AVL-P0-031 | Build repair/reindex with dry run, backup requirement, progress, verification, and audit. | Corrupt-index repair fixtures, full `swift test`, and operator repair acceptance. |
| AVL-P1-042 | Implementation remaining | AVL-P0-022 | Add batch printing and company/printer/voucher-type print profiles. | Batch/profile render fixtures, full `swift test`, and accountant print-run acceptance. |
| AVL-P1-043 | Implementation remaining | AVL-P1-042 | Add DSC PDF signing and structured XML interchange with explicit confirmation. | Certificate/token/XML fixtures, full `swift test`, and operator export/sign acceptance. |
| AVL-P1-009 | Implementation remaining | AVL-P0-011 | Add multi-currency books, rates, revaluation, and forex journals. | Multi-period FX fixtures, full `swift test`, and accountant forex acceptance. |
| AVL-P1-012 | Implementation remaining | AVL-P0-010 | Add godown/transit ledger with transfer ownership and in-transit valuation. | Dispatch/receipt fixtures, full `swift test`, and stock-transfer acceptance. |
| AVL-P1-013 | Implementation remaining | AVL-P0-010 | Add expired-batch enforcement with override policy and audit. | Expiry fixtures, full `swift test`, and stock-control acceptance. |
| AVL-P1-014 | Implementation remaining | AVL-P0-009 and AVL-P0-010 | Add by-product and scrap lines to manufacturing vouchers. | BOM production fixtures, full `swift test`, and manufacturing acceptance. |
| AVL-P1-015 | Implementation remaining | AVL-P0-010 | Add configurable negative-stock valuation and later-receipt adjustment. | Negative-stock timeline fixtures, full `swift test`, and stock-valuation acceptance. |

## Wave P2 — post-launch polish

Execute only after P0 release readiness is real and P1 rollout blockers are closed.

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P2-011 | Implementation remaining | AVL-P0-032 | Add duplicate voucher flow with lineage and fresh numbering. | Duplicate/edit/save fixtures, full `swift test`, and accountant copy-flow acceptance. |
| AVL-P2-012 | Implementation remaining | AVL-P0-018 | Add narration recall with privacy-aware history rules. | Recall fixtures, full `swift test`, and keyboard acceptance. |
| AVL-P2-013 | Implementation remaining | AVL-P1-037 | Add insert-while-browsing and PgUp/PgDn voucher navigation. | Browse/insert navigation fixtures, full `swift test`, and accountant browse-flow acceptance. |
| AVL-P2-014 | Implementation remaining | AVL-P0-011 | Add inline calculator in amount fields without float drift. | Expression fixtures, full `swift test`, and keyboard acceptance. |
| AVL-P2-015 | Implementation remaining | AVL-P1-036 | Add report-line zoom and restore prior context. | Drill-return fixtures, full `swift test`, and report-usage acceptance. |
| AVL-P2-016 | Implementation remaining | AVL-P0-022 | Add explicit-confirmation email dispatch with PDF attachment. | Cancel/auth/retry fixtures, full `swift test`, and operator send-flow acceptance. |
| AVL-P2-019 | Implementation remaining | None | Add Gateway-style dashboard with dense company/report quick access. | Navigation/accessibility fixtures, full `swift test`, and accountant dashboard acceptance. |
| AVL-P2-020 | Implementation remaining | None | Split company capabilities from per-screen configuration in F11/F12 style. | Screen/config context fixtures, full `swift test`, and accountant settings acceptance. |
| AVL-P2-001 | Implementation remaining | AVL-P1-042 | Add cheque-printing template designer. | Template render fixtures, full `swift test`, and print acceptance. |
| AVL-P2-002 | Implementation remaining | AVL-P1-010 | Add budget-versus-actual variance reports. | Budget reconciliation fixtures, full `swift test`, and reporting acceptance. |
| AVL-P2-003 | Implementation remaining | AVL-P0-010 | Add orphaned-batch detection and resolution. | Repair fixtures, full `swift test`, and stock-control acceptance. |
| AVL-P2-004 | Implementation remaining | AVL-P1-004 | Cover leap-year payroll edge cases. | Leap-year fixtures, full `swift test`, and payroll acceptance. |
| AVL-P2-005 | Implementation remaining | AVL-P0-022 | Add regional-script PDF font embedding. | Render/extraction fixtures, full `swift test`, and document acceptance. |
| AVL-P2-006 | Implementation remaining | AVL-P1-028 | Add MT940 and CAMT.053 bank imports. | Bank-format fixtures, full `swift test`, and import acceptance. |
| AVL-P2-007 | Implementation remaining | AVL-P1-028 | Add explainable fuzzy reconciliation. | Confidence fixtures, full `swift test`, and bank-reco acceptance. |
| AVL-P2-008 | Implementation remaining | AVL-P0-030 | Add multi-company consolidation and elimination entries. | Intercompany fixtures, full `swift test`, and finance acceptance. |
| AVL-P2-009 | Implementation remaining | None | Improve XLSX export formatting fidelity. | Workbook fixtures, full `swift test`, and export acceptance. |
| AVL-P2-010 | Implementation remaining | None | Add hardware-independent licensing and recovery. | Device-replacement fixtures, full `swift test`, and operator acceptance. |
| AVL-P2-017 | Implementation remaining | AVL-P1-043 | Add legacy ASCII/SDF/HTML export compatibility. | Encoding/schema fixtures, full `swift test`, and export acceptance. |
| AVL-P2-018 | Implementation remaining | None | Expand discoverable shortcut catalogue beyond the daily-use matrix. | Conflict-audit fixtures, full `swift test`, and help/discovery acceptance. |

## Current proof notes for already-advanced P0 items

These items stay open here because proof closure is still incomplete even though implementation has advanced substantially:

- `AVL-P0-002`, `AVL-P0-011`, `AVL-P0-025`, `AVL-P0-026`, `AVL-P0-027`, and `AVL-P0-030` remain `Proof remaining`.
- `AVL-P0-012` is also `Proof remaining`; targeted tamper evidence is green on:
  - `swift test --filter AuditTamperEvidenceTests`
  - `swift test --filter DatabaseManagerFileResolutionTests`
  - `swift test --filter AuditRepositoryTests`
  - `swift test --filter SchemaDriftTests`
- None of those items may move to `Manual acceptance remaining` until relevant full-suite proof is rerun from the current worktree after any dependent changes.

## Wave P0-A evidence log

### AVL-P0-012

- Implemented: [Avelo/Core/Services/AuditChainIntegrity.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/AuditChainIntegrity.swift), [Avelo/Core/Repositories/AuditRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/AuditRepository.swift), [Avelo/Core/Database/DatabaseManager.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/DatabaseManager.swift), and [Avelo/Core/Database/RestoreService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/RestoreService.swift). Invariant: every audit event is sequence-linked and HMAC-signed from the company key, restore remaps rebuild the chain for the new company identity, and company open fails closed on tampered or mismatched chains.
- Automated proof:
  - `swift test --filter AuditTamperEvidenceTests` — pass
  - `swift test --filter DatabaseManagerFileResolutionTests` — pass
  - `swift test --filter AuditRepositoryTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test --filter RestoreServiceTests` — pass
  - `swift test --filter AppEnvironmentFlowTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test --filter BalanceSheetReconciliationTests` — pass
  - `swift test --filter ProfitLossReconciliationTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a company, post at least one voucher, export a backup, and restore it into a new company entry.
  2. Open the restored company and confirm it loads without an integrity warning.
  3. Close Avelo, tamper with the restored company database by changing one row in `avelo_audit_events` or deleting one audit row, then reopen Avelo.
  4. Attempt to open the tampered company from the picker.
  5. Expected result: Avelo refuses to open the company, reports audit-chain verification failure clearly, does not silently repair or continue, and untampered companies still open normally.
  6. Restore the original untampered backup again and verify the re-restored company opens and reports remain readable.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-012 closure evidence.

### AVL-P0-011

- Implemented: [Avelo/Core/Utilities/Currency.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Utilities/Currency.swift), [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), [Avelo/Core/Validation/StockMovementValidator.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Validation/StockMovementValidator.swift), [Avelo/Core/Repositories/ReportRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository.swift), [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), and related checked-math callers. Invariant: money/quantity arithmetic, reductions, and `Int64.min` formatting fail closed with explicit errors instead of trapping, wrapping, or silently saturating.
- Automated proof:
  - `swift test --filter CurrencyTests` — pass
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test --filter Phase6MathRoundingTests` — pass
  - `swift test --filter Phase6HardeningTests` — pass
  - `swift test --filter VoucherDraftTests` — pass
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test --filter BankReconciliationServiceTests` — pass
  - `swift test --filter AccountTreeReconciliationTests` — pass
  - `swift test --filter InvoicePDFServiceTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. In a test company, prepare one voucher draft, one payroll entry, one bank import line, and one inventory movement near known numeric boundaries.
  2. Try posting values that should still succeed at the edge of valid range, including the largest negative displayable amount and normal high-value voucher totals.
  3. Then try one clearly overflowing amount in each flow: voucher total, payroll net, inventory quantity × rate, and bank statement amount.
  4. Open the affected reports and invoice/PDF export flow for the valid entries.
  5. Expected result: valid boundary values save and display correctly; invalid overflowing values are rejected with explicit validation/business-rule errors; the app never crashes, never shows wrapped amounts, and never exports a PDF with corrupted totals.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-011 closure evidence.

### AVL-P0-025

- Implemented: [Avelo/Core/Validation/FinancialYearInputValidator.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Validation/FinancialYearInputValidator.swift), [Avelo/Core/Utilities/FiscalLockChecker.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Utilities/FiscalLockChecker.swift), [Avelo/Core/Database/Migrations/MigrationV010.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV010.swift), and restore validation in [Avelo/Core/Database/RestoreService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/RestoreService.swift). Invariant: overlapping financial years are rejected on create/update/restore, adjacent years resolve to exactly one containing FY, and corrupt ambiguity fails closed instead of returning an arbitrary row.
- Automated proof:
  - `swift test --filter FinancialYearServiceTests` — pass
  - `swift test --filter RestoreServiceTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. In Company Settings, create one FY covering `2024-04-01` to `2025-03-31`.
  2. Attempt to create a second FY that overlaps it by one day, one month, and a full contained range.
  3. Create an adjacent non-overlapping FY for `2025-04-01` to `2026-03-31`.
  4. Post or draft vouchers on the boundary dates `2025-03-31` and `2025-04-01`.
  5. Restore a backup whose FYs are known-good, then restore a deliberately corrupted backup with overlapping FY ranges.
  6. Expected result: overlapping FY creation/update is rejected with a clear validation error; adjacent FYs are accepted; boundary dates resolve into exactly one FY each; good backups restore normally; corrupted overlapping-FY backups fail closed before reopening books.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-025 closure evidence.

### AVL-P0-026

- Implemented: [Avelo/Core/Utilities/FiscalLockChecker.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Utilities/FiscalLockChecker.swift), fiscal-lock trigger coverage in [Avelo/Core/Database/Migrations/MigrationV011.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV011.swift), restore trigger recreation in [Avelo/Core/Database/RestoreService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/RestoreService.swift), and locked-write rejection paths exercised through banking, payroll, opening-balance, voucher, and inventory services. Invariant: locked-period voucher, line, stock, payroll, banking, and opening-balance mutations fail closed at both service and trigger boundaries, including voucher-date moves into locked FYs.
- Automated proof:
  - `swift test --filter FiscalLockEnforcementTests` — pass
  - `swift test --filter BankReconciliationServiceTests` — pass
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a company with one FY, post representative voucher, stock, payroll, and bank activity, then lock that FY.
  2. Attempt each locked-period mutation from the UI: edit an existing voucher, backdate a stock movement, import/clear a bank line in the locked range, edit opening balances, and post payroll into the locked FY.
  3. Attempt a voucher date edit that moves an otherwise valid voucher into the locked FY.
  4. Restore a backup of that company and repeat one voucher edit plus one bank/stock mutation in the restored copy.
  5. Expected result: every locked-period mutation is rejected with a clear lock error; no partial write persists; restored databases keep the same protection; current open FY work still succeeds normally.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-026 closure evidence.

### AVL-P0-030

- Implemented: [Avelo/Core/Database/Migrations/MigrationV014.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV014.swift), [Avelo/Core/Repositories/VoucherRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/VoucherRepository.swift), [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), and company-scoping guards exercised across banking, payroll, inventory, and voucher writes. Invariant: cross-company references fail closed at trigger and service boundaries, and read/write flows remain scoped to the active company instead of accepting foreign IDs that happen to satisfy standalone foreign keys.
- Automated proof:
  - `swift test --filter CompanyIsolationTests` — pass
  - `swift test --filter BankReconciliationServiceTests` — pass
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create two companies with distinct ledgers, bank accounts, inventory items, employees, and financial years.
  2. In Company A, attempt each foreign-reference action using an identifier from Company B: post a voucher against B's ledger, import or reconcile a bank line against B's bank account, record inventory against B's item, and post payroll using B's employee or financial year.
  3. Attempt the same actions once through the UI flow and once through any import/restore path that can surface raw IDs indirectly.
  4. Browse vouchers, ledgers, bank items, and stock views in Company A after the rejected actions.
  5. Expected result: every cross-company write is rejected with a clear ownership/isolation error; no partial rows persist; Company A lists only Company A data; Company B remains unaffected and fully readable.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-030 closure evidence.

### AVL-P0-027

- Implemented: [Avelo/Core/Database/SQLiteDatabase.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/SQLiteDatabase.swift), [Avelo/Core/Repositories/BankReconciliationRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/BankReconciliationRepository.swift), [Avelo/Core/Repositories/VoucherRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/VoucherRepository.swift), [Avelo/Core/Repositories/ReportRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository.swift), [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), and strict row decoders covered by [Tests/AveloTests/MalformedUUIDHandlingTests.swift](/Users/vaibhavkakar/Developer/Avelo/Tests/AveloTests/MalformedUUIDHandlingTests.swift). Invariant: malformed dates, enum codes, UUIDs, booleans, and missing columns are rejected explicitly at decode/open time instead of silently coercing to epoch dates, default enums, or partial rows.
- Automated proof:
  - `swift test --filter MalformedUUIDHandlingTests` — pass
  - `swift test --filter SQLiteDatabaseTests` — pass
  - `swift test --filter BankReconciliationServiceTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Start from a disposable backup copy of a valid company database.
  2. Corrupt one persisted field at a time: replace a voucher type with an unknown code, damage a UUID, remove a required column from a query/view path if supported by the fixture, and replace one ISO date with malformed text.
  3. Reopen the company and navigate to the affected workflow or report after each corruption.
  4. Attempt one read-only report and one write flow that would previously have defaulted the bad value.
  5. Expected result: Avelo fails closed with a clear data-corruption/decode error, does not reinterpret the row as Journal/Debit/FIFO/1970-01-01, and does not allow downstream posting from corrupted state.
  6. Restore the clean backup and confirm normal open/read/write behavior resumes.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-027 closure evidence.

### AVL-P0-002

- Implemented: [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), [Avelo/Core/Repositories/VoucherRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/VoucherRepository.swift), voucher-number sequencing in the database layer, and cancellation/reversal tests in [Tests/AveloTests/VoucherServiceTests.swift](/Users/vaibhavkakar/Developer/Avelo/Tests/AveloTests/VoucherServiceTests.swift). Invariant: successful posts allocate contiguous voucher numbers exactly once, failed posts and failed batch chunks do not consume numbers, and cancelled vouchers preserve history without allowing number reuse.
- Automated proof:
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test` — pass (`278` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a test company and post a known sequence of vouchers until you have at least five consecutive voucher numbers.
  2. Trigger one failed post and one failed batch chunk using a validation error, then post the next valid voucher.
  3. Cancel one existing voucher through the supported cancellation flow and then post another new voucher.
  4. If a concurrent-entry screen is available, submit two valid vouchers near-simultaneously from separate windows or rapid user actions.
  5. Expected result: only successful vouchers consume numbers; failed attempts leave no gaps; cancellation keeps the original voucher number in history and the next new voucher gets a new sequential number; concurrent successes remain gap-free and unique.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-002 closure evidence.

## Wave P0-B evidence log

### AVL-P0-005

- Implemented: [Avelo/Core/Services/FinancialYearService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/FinancialYearService.swift), [Avelo/Core/Repositories/FinancialYearOpeningBalanceRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/FinancialYearOpeningBalanceRepository.swift), [Avelo/Core/Repositories/FinancialYearRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/FinancialYearRepository.swift), [Avelo/Core/Repositories/ReportRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository.swift), [Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository+FinancialStatements.swift), [Avelo/Core/Cache/AccountTree.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Cache/AccountTree.swift), [Avelo/Core/Cache/AccountTreeCache.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Cache/AccountTreeCache.swift), [Avelo/Core/Database/Migrations/MigrationV014.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV014.swift), [Avelo/Core/Database/MigrationRunner.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/MigrationRunner.swift), and [Avelo/Core/Database/SchemaVersion.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/SchemaVersion.swift). Invariant: closing an FY publishes one exact carry-forward opening snapshot into the next FY, repeating close is idempotent, reopening removes the published carry-forward rows, and later-FY reports/account trees resolve opening balances from the authoritative carry-forward snapshot or deterministic fallback math rather than mutating historical ledger masters.
- Automated proof:
  - `swift test --filter FinancialYearCloseCarryForwardTests` — pass
  - `swift test --filter FinancialYearServiceTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test --filter AccountTreeReconciliationTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test` — pass (`283` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create two adjacent financial years for one company, with the earlier FY still open and the later FY empty.
  2. Post representative asset, liability, income, and expense activity in the earlier FY so at least one ledger closes debit and one closes credit.
  3. Close the earlier FY once, open the later FY reports, and verify ledger report, trial balance, balance sheet, and account tree starting balances all match the prior FY closing balances exactly.
  4. Attempt to close the same FY again and verify no second carry-forward layer or duplicate opening snapshot is created.
  5. Reopen the earlier FY through the maintenance/test flow, confirm the later FY carry-forward snapshot is removed, then close it again and confirm the regenerated opening snapshot still matches the revised prior-year closing balances exactly.
  6. Expected result: close publishes one exact opening snapshot into the next FY, repeated close is a no-op, reopen removes the published carry-forward state cleanly, re-close republishes the correct balances, and no historical ledger master opening balance is overwritten.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-005 closure evidence.

### AVL-P0-006

- Implemented: [Avelo/Features/Vouchers/EditVoucherSheet.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Vouchers/EditVoucherSheet.swift) and [Avelo/Features/Vouchers/ReverseVoucherSheet.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Vouchers/ReverseVoucherSheet.swift), on top of the existing locked-FY service enforcement in [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift) and validator/lock checks in [Avelo/Core/Validation/VoucherDraftValidator.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Validation/VoucherDraftValidator.swift). Invariant: a voucher belonging to a locked or closed FY is presented read-only, in-place edit remains blocked, and the correction path is an explicitly linked reversal that posts into the current open FY while preserving the original voucher and audit history.
- Automated proof:
  - `swift test --filter VouchersViewTests` — pass
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter FiscalLockEnforcementTests` — pass
  - `swift test` — pass (`285` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a company with one voucher in an FY, then lock that FY and keep or create a later open FY.
  2. Open the locked-period voucher from the voucher list or any report drill-down entry point.
  3. Verify the sheet is read-only, clearly explains that the period is locked, and offers a reversal action instead of a save path.
  4. Use the reversal workflow, enter an optional reason, and complete the reversal.
  5. Verify the original voucher remains unchanged in the locked FY, the reversal voucher is linked to it, and the reversal lands in the latest open FY with opposite debit/credit lines.
  6. Attempt a direct edit of the locked voucher through any remaining service/UI path and confirm it is rejected cleanly with no partial write and no crash.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-006 closure evidence.

### AVL-P0-007

- Implemented: [Avelo/Features/Vouchers/NewVoucherSheet.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Vouchers/NewVoucherSheet.swift). Invariant: the new-voucher default action can start posting only once per in-flight attempt, so rapid repeated `Enter`/default-action dispatch cannot create duplicate vouchers or duplicate audit events from a single visible posting action.
- Automated proof:
  - `swift test --filter VouchersViewTests` — pass
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter AccountantRCFlowTests` — pass
  - `swift test` — pass (`287` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Open a new voucher sheet in an unlocked FY and enter one valid balanced voucher.
  2. Trigger the post action repeatedly using rapid `Enter`/default-action activation and an immediate mouse click on Post while the sheet is still visible.
  3. Reopen the voucher list and audit trail for the affected voucher type and date.
  4. Repeat once more with a second valid voucher after the first post completes, confirming the guard resets for a new attempt.
  5. Expected result: each intentional voucher post produces exactly one durable voucher number, one voucher row, and one audit event; no duplicate voucher is created from rapid repeated activation during the same in-flight post; after completion, a new deliberate post still succeeds normally.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-007 closure evidence.

### AVL-P0-003

- Implemented: [Avelo/Core/Database/Migrations/MigrationV015.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV015.swift), [Avelo/Core/Repositories/AccountingWorkflowsRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/AccountingWorkflowsRepository.swift), [Avelo/Core/Services/BillAllocationEngine.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/BillAllocationEngine.swift), [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), [Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift), [Avelo/Core/Database/RestoreService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/RestoreService.swift), [Avelo/Features/Vouchers/EditVoucherSheet.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Vouchers/EditVoucherSheet.swift), [Avelo/Core/Models/ReportResult.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Models/ReportResult.swift), and [Avelo/Features/Reports/ReportsBody+Outstanding.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Reports/ReportsBody+Outstanding.swift). Invariant: bill allocations are persisted in-schema, receipts/payments/advances/on-account amounts settle FIFO by party with explicit `Agst Ref` support, outstanding is bill-wise rather than party-netted, edits update allocations, reversals/cancellations mirror allocations for net settlement, and restore/remap keeps the new table company-safe.
- Automated proof:
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test --filter RestoreServiceTests` — pass
  - `swift test --filter AccountantRCFlowTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test` — pass (`290` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a debtor and a creditor party ledger, then post two bills for one party with distinct bill references.
  2. Post one on-account receipt/payment smaller than the total outstanding and verify the oldest open bill is consumed first without manual reference selection.
  3. Post one explicit `Against Ref` settlement against the remaining later bill and verify only that named bill is reduced.
  4. Open Outstanding as of the settlement date and confirm rows are bill-wise, carry the correct reference numbers, and reconcile exactly to the party ledger balance.
  5. Edit one still-open bill to change its amount/reference, then cancel or reverse another bill and verify outstanding updates correctly without reusing numbers or deleting history.
  6. Export a backup, restore it into a new company, reopen the restored bill, and confirm the bill reference and outstanding result still match the source company.
  7. Expected result: FIFO and explicit-reference settlement both reconcile exactly, outstanding never falls back to party-netted balances, reversals/cancellations net the original bill safely, and restore preserves the workflow state.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as P0-003 closure evidence.

### AVL-P0-009

- Implemented: [Avelo/Core/Database/Migrations/MigrationV017.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV017.swift), [Avelo/Core/Database/MigrationRunner.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/MigrationRunner.swift), [Avelo/Core/Database/SchemaVersion.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/SchemaVersion.swift), [Avelo/Core/Repositories/BOMRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/BOMRepository.swift), [Avelo/Core/Services/BOMService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/BOMService.swift), and [Avelo/Core/Database/RestoreService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/RestoreService.swift). Invariant: one persisted BOM per assembly item is stored under same-company constraints, component rows are replaced atomically for that BOM, and save fails closed before persistence whenever the proposed assembly graph introduces a direct or indirect cycle.
- Automated proof:
  - `swift test --filter 'BOMServiceTests|SchemaDriftTests|RestoreServiceTests'` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Enable inventory for a test company and create at least three stock items intended to act as assemblies plus one raw component.
  2. Save one simple BOM and reopen it to confirm output quantity, component quantities, and component order round-trip exactly.
  3. Attempt a direct self-reference by adding the assembly item as its own component and save again.
  4. Create an indirect chain `A -> B`, `B -> C`, then attempt to save `C -> A`.
  5. Export and restore the company backup, reopen the restored company, and reload the previously valid BOM.
  6. Expected result: valid BOMs persist and reload unchanged; direct and indirect cycles are rejected with an explicit circular-BOM error before any partial write; restored companies preserve valid BOM definitions without cross-company corruption.
- Residual risk: Manual manufacturing acceptance is still pending; broader BOM costing and production workflows remain open in later backlog items and are not counted as AVL-P0-009 closure evidence.

### AVL-P0-008

- Implemented: [Avelo/Core/Utilities/ExactQuantity.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Utilities/ExactQuantity.swift), [Avelo/Core/Models/InventoryItem.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Models/InventoryItem.swift), [Avelo/Core/Repositories/InventoryRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/InventoryRepository.swift), [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), and [Avelo/Core/Database/Migrations/MigrationV005.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV005.swift). Invariant: alternate-UOM definitions persist as exact numerator/denominator ratios, stock movements entered in the alternate unit convert to authoritative base quantity through checked integer math, and fractional residual base quantity is preserved without float truncation.
- Automated proof:
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Enable inventory for a test company and create one stock item with a base unit plus an alternate unit whose conversion is fractional, for example `1 BAG = 2.5 KG`.
  2. Reopen the saved stock item and verify the alternate-unit definition still shows exactly the original ratio, not a rounded decimal approximation.
  3. Post one stock-in movement entered as `1 BAG`, then inspect the stored/base quantity through stock ledger or movement detail.
  4. Post another movement entered as a fractional alternate quantity such as `1.5 BOX` for an item with an exact whole conversion like `12 NOS per BOX`.
  5. Expected result: the authoritative base quantities resolve exactly from the rational conversion (`1 BAG = 5/2 KG`, `1.5 BOX = 18 NOS`), no truncation or silent rounding occurs, and downstream stock balances/valuation use those exact converted quantities.
- Residual risk: Manual accountant acceptance is still pending; broader valuation and ageing acceptance remain tracked under later dependent tickets and are not counted as AVL-P0-008 closure evidence.

### AVL-P0-010

- Implemented: [Avelo/Core/Services/InventoryValuationEngine.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryValuationEngine.swift), [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), [Avelo/Core/Repositories/InventoryRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/InventoryRepository.swift), [Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository+ComplianceReports.swift), and [Avelo/Core/Models/ReportResult.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Models/ReportResult.swift). Invariant: each replay derives authoritative stock-out value from persisted movements and surviving layers, FIFO consumes oldest layers, weighted average consumes exact aggregate quantity/value with deterministic residual paise allocation, and reports reflect replayed authoritative quantity/value rather than caller-supplied stock-out rates.
- Automated proof:
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create one FIFO-valued item and one weighted-average-valued item in an inventory-enabled company.
  2. For the FIFO item, post at least two receipts at different rates, then post one stock-out with an intentionally wrong caller rate and verify the persisted stock-out value follows oldest-layer cost, not the entered rate.
  3. For the weighted-average item, post at least two receipts at different rates, then post one stock-out and verify the persisted stock-out value follows the exact aggregate average and leaves the expected closing value.
  4. Use one quantity/value mix that produces residual paise and verify the remaining stock value is deterministic and repeatable after reload.
  5. Open the stock valuation report for the same date range and confirm quantity, out value, closing value, and average cost reconcile to the replayed movements exactly.
  6. Expected result: FIFO and weighted-average items both ignore caller-supplied stock-out rates, consumed value is authoritative and deterministic, residual paise allocation is stable, and the report ties exactly to persisted movements and closing stock.
- Residual risk: Manual accountant acceptance is still pending; ageing and other downstream inventory workflows remain tracked under later dependent tickets and are not counted as AVL-P0-010 closure evidence.

### AVL-P0-024

- Implemented: [Avelo/Core/Repositories/ReportRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/ReportRepository.swift), [Avelo/Core/Services/ReportService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/ReportService.swift), [Avelo/Features/Reports/ReportsBody+FinancialStatements.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Reports/ReportsBody+FinancialStatements.swift), and [Avelo/Features/Dashboard/DashboardView.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Features/Dashboard/DashboardView.swift). Invariant: every trial-balance row is netted to exactly one closing side by combining signed opening balance with movement debits/credits first, and only the resulting net amount is exposed as debit or credit for that account.
- Automated proof:
  - `swift test --filter TrialBalanceNettingTests` — pass
  - `swift test --filter AccountTreeReconciliationTests` — pass
  - `swift test --filter ReportBehaviorTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create or use a company where one account has an opening balance on one side and later movement on the opposite side, for example opening cash `₹100 Dr` plus `₹40 Cr` movement.
  2. Open Trial Balance as of the period end and inspect that account row directly.
  3. Verify the same company through the account tree/dashboard trial-balance view and confirm the signed net agrees with the report row.
  4. Repeat once after bill-allocation, cancellation/reversal, and FY carry-forward activity exists in the same company.
  5. Expected result: each account appears on exactly one closing side, `₹100 Dr` plus `₹40 Cr` reports `₹60 Dr` rather than separate debit and credit columns, total debits equal total credits, and the report matches both seeded/live SQL reconciliation and later-FY carry-forward behavior.
- Residual risk: Manual accountant acceptance is still pending; benchmark/stress skips remain historical and are not counted as AVL-P0-024 closure evidence.

### AVL-P0-019

- Implemented: [Avelo/Core/Services/InventoryService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryService.swift), [Avelo/Core/Services/InventoryValuationEngine.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/InventoryValuationEngine.swift), and [Avelo/Core/Repositories/InventoryRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/InventoryRepository.swift). Invariant: any stock movement added or corrected with an effective date at or before later movements triggers authoritative replay from the earliest affected date, republishes corrected downstream `total_value_paise` values atomically, and returns a publication payload listing every movement whose persisted valuation changed.
- Automated proof:
  - `swift test --filter InventoryServiceTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create an item with at least one later stock-out already posted.
  2. Insert a new earlier-dated receipt and verify the later stock-out value changes to the newly authoritative value and the closing stock value updates accordingly.
  3. Reverse one existing stock-out and verify stock quantity/value return to the expected restored state with a published recalculation result.
  4. Replace one earlier receipt or issue with a corrected movement and verify downstream later movements are republished with their corrected authoritative values.
  5. Expected result: backdated insert, reversal, and replacement all update downstream persisted valuations deterministically; the affected movement list identifies changed downstream rows; no partial or silent stale valuation remains after the write commits.
- Residual risk: Manual accountant acceptance is still pending; explicit inventory-voucher cancellation and broader downstream inventory workflows remain outside this shipped movement-lifecycle proof and are not counted as AVL-P0-019 closure evidence.

### AVL-P0-001

- Implemented: [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), [Avelo/Core/Database/Migrations/MigrationV008.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV008.swift), [Avelo/Core/Database/SeedLoader.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/SeedLoader.swift), and [Avelo/Resources/Seed/DefaultChartOfAccounts.json](/Users/vaibhavkakar/Developer/Avelo/Avelo/Resources/Seed/DefaultChartOfAccounts.json). Invariant: invoice-style GST drafts strip any caller-supplied `ROUND_OFF` line, recompute one authoritative round-off line deterministically from the non-round-off GST-bearing lines, and append it at a stable position only when the bounded mismatch rule applies.
- Automated proof:
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter SchemaDriftTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Create a GST-bearing sales voucher whose debit/credit mismatch is within the allowed paise-level auto-balance threshold.
  2. Include no round-off line the first time, then reopen/edit the same invoice while deliberately entering an incorrect manual `ROUND_OFF` line.
  3. Save the edit and inspect the persisted voucher lines.
  4. Post one non-GST or no-tax-ledger voucher with a similar mismatch and confirm it still fails instead of auto-balancing.
  5. Expected result: the GST invoice persists exactly one `ROUND_OFF` line with the deterministic side and paise amount, any caller-supplied round-off line is replaced rather than preserved, the voucher total reflects the normalized posting, and non-GST mismatches still fail closed.
- Residual risk: Manual accountant acceptance is still pending; legal PDF completeness and signed-QR/e-invoice workflows remain separate later tickets and are not counted as AVL-P0-001 closure evidence.

### AVL-P0-032

- Implemented: [Avelo/Core/Services/VoucherService.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Services/VoucherService.swift), [Avelo/Core/Repositories/VoucherRepository.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Repositories/VoucherRepository.swift), [Avelo/Core/Models/Voucher.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Models/Voucher.swift), and [Avelo/Core/Database/Migrations/MigrationV007.swift](/Users/vaibhavkakar/Developer/Avelo/Avelo/Core/Database/Migrations/MigrationV007.swift). Invariant: cancellation preserves the original voucher row and number, records cancelled status plus reason/actor/timestamp/linkage metadata, creates an explicit linked reversal rather than deleting history, and writes both reversal and cancellation audit events.
- Automated proof:
  - `swift test --filter VoucherServiceTests` — pass
  - `swift test --filter AuditCoverageTests` — pass
  - `swift test` — pass (`296` passed, `8` skipped, `0` failed)
- Manual proof:
  1. Post one voucher, note its number, then cancel it through the supported cancellation flow with a reason and actor.
  2. Reopen the original voucher and confirm it remains visible with cancelled status plus persisted reason, actor, timestamp, and linked cancellation voucher ID.
  3. Open the linked reversal voucher and confirm it carries reversed lines and source linkage to the original voucher.
  4. Post a new voucher of the same type and confirm the cancelled number is not reused.
  5. Attempt to edit or cancel the already cancelled voucher again and confirm both actions fail cleanly.
  6. Check the audit trail and confirm both `voucherReversed` and `voucherCancelled` events exist with snapshot data.
  7. Expected result: cancellation never deletes the source voucher or its number, history remains intact, the linked reversal preserves accounting traceability, and repeated cancellation/edit attempts are blocked.
- Residual risk: Manual accountant acceptance is still pending; broader Day Book and continuous-flow browse/cancel UX remains tracked in later dependent tickets and is not counted as AVL-P0-032 closure evidence.
