# AVELO Master Execution Checklist

## Summary

This file is the remaining-work execution queue. It tracks only unfinished `AVL-*` backlog items from `Docs/Avelo_Release_Board.md`, grouped into dependency-ordered waves through P2.

Rules:

- `Docs/Avelo_Release_Board.md` remains the canonical source of truth for backlog scope, dependencies, and proof-of-done.
- Historical `RB-*` work is evidence only and does not appear in the active queue here.
- An item stays in this checklist until its implementation, automated proof, relevant full-suite proof, and manual accountant acceptance are all recorded.
- Release verdict remains `NOT READY` while any `AVL-P0-*` row is still open on the board.

Execution states:

- `Implementation remaining` — code, schema, workflow, or UI behavior is still missing.
- `Proof remaining` — implementation has landed substantially, but targeted/full-suite/manual proof is still incomplete.
- `Manual acceptance remaining` — automated proof is complete enough to stop coding, but accountant QA is still pending.

Evidence template required before striking an item:

- `Implemented`: code path and invariant now exist.
- `Automated proof`: exact targeted test commands.
- `Manual proof`: accountant scenario, steps, and expected output/result.
- `Residual risk`: blank if closed; explicit if reopened or partially blocked.

## Release gate policy

### P0 gate

Before calling Avelo release-ready:

- no `AVL-P0-*` remains open on the board
- every P0 item has targeted automated proof
- relevant `swift test` full-suite proof is recorded
- every P0 item has a written manual accountant acceptance script and completed result

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
| AVL-P0-012 | Proof remaining | None | Keep keyed audit chain implementation; run targeted tamper suites plus full `swift test`; write accountant verification script for tamper rejection on company open/repair paths. | Full-suite proof and manual accountant acceptance. Targeted proof now includes `swift test --filter AuditTamperEvidenceTests`, `swift test --filter DatabaseManagerFileResolutionTests`, `swift test --filter AuditRepositoryTests`, and `swift test --filter SchemaDriftTests`. |
| AVL-P0-011 | Proof remaining | None | Complete any remaining arithmetic-path audit, then rerun the overflow suites and full `swift test`; write accountant overflow acceptance scenarios for voucher, payroll, reports, and banking. | Confirm no uncovered money/quantity path remains, plus full-suite proof and manual acceptance. |
| AVL-P0-025 | Proof remaining | AVL-P0-023 behavior must stay consistent | Rerun FY overlap, restore, and schema tests after any date-semantics changes; write accountant script for overlapping-FY rejection and deterministic date resolution. | Full-suite proof and manual acceptance. |
| AVL-P0-026 | Proof remaining | AVL-P0-025 | Reconfirm all locked-period write paths after any follow-on FY work; write accountant script for voucher, stock, payroll, banking, and opening-balance lock rejection. | Full-suite proof and manual acceptance. |
| AVL-P0-030 | Proof remaining | None | Reconfirm cross-company guards after company-create and registry work; write accountant script for company-isolation rejection at service/UI level. | Full-suite proof and manual acceptance. |
| AVL-P0-027 | Proof remaining | None | Re-run strict-decoding suites after any repository/schema edits; write accountant corruption-handling script for fail-closed open/read behavior. | Full-suite proof and manual acceptance. |
| AVL-P0-002 | Proof remaining | None | Re-run contention/rollback numbering tests after duplicate-submit and cancellation work; write accountant script for contiguous numbering under failure/retry. | Full-suite proof and manual acceptance. |

## Wave P0-B — remaining accounting and fiscal blockers

Execute in this order after Wave P0-A is green enough to avoid rework.

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P0-005 | Implementation remaining | AVL-P0-025 and AVL-P0-026 | Implement locked-FY close carry-forward with exact-once opening propagation and reopen/idempotency rules. | Golden close/reopen/idempotency fixtures, full `swift test`, and accountant year-close acceptance. |
| AVL-P0-006 | Implementation remaining | AVL-P0-026 | Implement reversal-only correction flow for locked-FY edits across service and UI. | UI/service rejection-and-reversal tests, full `swift test`, and accountant locked-period correction acceptance. |
| AVL-P0-007 | Implementation remaining | AVL-P0-002 | Implement one-shot submit protection for rapid Enter/default-action activation without duplicate audit events. | Repeated-key/concurrent-submit fixtures, full `swift test`, and keyboard-entry acceptance. |
| AVL-P0-003 | Implementation remaining | None | Replace bill-allocation stub behavior with real FIFO settlement for receipts, payments, advances, and on-account amounts. | Golden bill-allocation fixtures, full `swift test`, and accountant outstanding reconciliation acceptance. |
| AVL-P0-004 | Implementation remaining | AVL-P0-003 | Implement non-destructive bounced-cheque workflow using linked reversals and re-presentation state. | Golden cheque lifecycle fixtures, full `swift test`, and accountant cheque reversal acceptance. |
| AVL-P0-009 | Implementation remaining | AVL-P0-011 | Implement direct and indirect BOM cycle detection before expansion/costing. | Cycle fixtures, full `swift test`, and manufacturing validation acceptance. |
| AVL-P0-008 | Proof remaining | AVL-P0-011 | Reconfirm rational alternate-UOM behavior after valuation, stock ageing, and logistics workflows settle; write accountant unit-conversion script. | Full-suite proof and manual acceptance. |
| AVL-P0-010 | Proof remaining | AVL-P0-008 and AVL-P0-011 | Reconfirm FIFO/weighted-average valuation against the final stock workflow set; write accountant valuation verification script. | Full-suite proof and manual acceptance. |
| AVL-P0-024 | Proof remaining | AVL-P0-011 | Reconfirm per-account trial-balance netting after bill allocation, cancellation, and FY close work; write accountant TB verification script. | Full-suite proof and manual acceptance. |
| AVL-P0-019 | Proof remaining | AVL-P0-010 | After `AVL-P0-003`/`AVL-P0-004`/`AVL-P0-009`, rerun downstream recalculation proofs and write accountant backdated-stock correction script. | Full-suite proof and manual acceptance. |
| AVL-P0-001 | Proof remaining | None | Reconfirm deterministic `ROUND_OFF` behavior after later voucher-class, GST, and print changes; write accountant invoice-rounding script. | Full-suite proof and manual acceptance. |
| AVL-P0-032 | Proof remaining | AVL-P0-002 and AVL-P0-012 | Reconfirm cancel/reversal/history behavior after numbering and tamper finalization; write accountant voucher-cancel acceptance script. | Full-suite proof and manual acceptance. |

Exit criteria for this wave:

- every ledger-impacting path has golden fixtures
- every workflow has an explicit accountant acceptance script
- no bill-wise, cheque, or BOM stub is still treated as acceptable readiness evidence

## Wave P0-C — storage, UI, and legal blockers

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P0-028 | Implementation remaining | None | Replace registry `INSERT OR REPLACE` with collision-safe insert/update semantics that preserve every company row and file. | Collision fixtures, full `swift test`, and accountant company-picker preservation acceptance. |
| AVL-P0-031 | Implementation remaining | None | Make schema-version reads throwing so unreadable DBs never fall back to version zero. | Corrupt/locked/wrong-key/I/O fixtures, full `swift test`, and operator recovery acceptance. |
| AVL-P0-029 | Implementation remaining | AVL-P0-028 and AVL-P0-031 | Make company creation transactional across DB file, Keychain, seed data, and registry with compensating cleanup and honored `seedDefaults`. | Failure-at-each-stage fixtures, full `swift test`, and accountant company-create rollback acceptance. |
| AVL-P0-013 | Implementation remaining | None | Exclude registry, DB, WAL, SHM, and recovery artifacts from iCloud sync. | Metadata fixture, clean-device verification, and operator storage acceptance. |
| AVL-P0-014 | Implementation remaining | None | Hold and release `ProcessInfo` activity assertions around migrations, restore, backup, repair, and recalculation. | Cancellation/error-release tests, full `swift test`, and sleep/App Nap QA. |
| AVL-P0-015 | Implementation remaining | AVL-P0-031 | Move migrations off the main thread with progress, interruption policy, and recovery UI. | Large-migration responsiveness/interruption fixtures, full `swift test`, and operator migration acceptance. |
| AVL-P0-016 | Implementation remaining | None | Consolidate company/router/editor state into one source of truth and remove stale pointer paths. | Company-switch/window/sheet stress tests, full `swift test`, and accountant shell-flow acceptance. |
| AVL-P0-017 | Implementation remaining | None | Guarantee `sqlite3_finalize`/reset/clear on every statement lifecycle path. | Fault-injection/leak fixtures, full `swift test`, and operational leak-free acceptance. |
| AVL-P0-018 | Implementation remaining | None | Add draft autosave and crash recovery without automatic posting or duplicate posting. | Kill/relaunch recovery fixtures, full `swift test`, and accountant draft-recovery acceptance. |
| AVL-P0-020 | Implementation remaining | None | Make voucher-grid `@FocusState` navigation reliable for Tab/Shift-Tab/Enter and row mutations. | Full keyboard matrix tests, full `swift test`, and keyboard-entry acceptance. |
| AVL-P0-021 | Implementation remaining | None | Add locale-aware decimal parsing with unambiguous paise storage and paste handling. | Locale round-trip fixtures, full `swift test`, and accountant locale-entry acceptance. |
| AVL-P0-023 | Implementation remaining | None | Force IST accounting calendar semantics regardless of device timezone. | Boundary/date-zone fixtures, full `swift test`, and accountant FY/GST period acceptance. |
| AVL-P0-022 | Implementation remaining | AVL-P1-008 | Finish GST-compliant PDF/invoice output, including mandatory fields and applicable signed QR behavior after e-invoice support lands. | Field-matrix and rendered-PDF fixtures, full `swift test`, and accountant legal-document acceptance. |

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
| AVL-P1-044 | Implementation remaining | AVL-P0-020 | Implement context-aware Tally/macOS shortcut engine without breaking text entry. | Full shortcut matrix, full `swift test`, and accountant keyboard-flow acceptance. |

## Wave P1-B — compliance and filing

| ID | State | Dependency gate | Next concrete action | Proof still missing |
| --- | --- | --- | --- | --- |
| AVL-P1-004 | Implementation remaining | None | Implement PF, ESI, Professional Tax, and payroll effective-rate rounding. | Golden payroll fixtures, full `swift test`, and payroll-operator acceptance. |
| AVL-P1-005 | Implementation remaining | None | Build Form 16 and 24Q/26Q exports with schema validation. | Export-schema fixtures, full `swift test`, and payroll filing acceptance. |
| AVL-P1-006 | Implementation remaining | AVL-P1-005 | Add 27Q/27EQ and correction/export workflows. | Validation fixtures, full `swift test`, and filing acceptance. |
| AVL-P1-008 | Implementation remaining | AVL-P0-022 legal print dependency | Implement e-invoice IRN lifecycle, reporting-window rules, signed JSON/QR storage, verification, and cancellation. | IRN lifecycle fixtures, full `swift test`, and accountant e-invoice acceptance. |
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

- `AVL-P0-001`, `AVL-P0-002`, `AVL-P0-008`, `AVL-P0-010`, `AVL-P0-011`, `AVL-P0-019`, `AVL-P0-024`, `AVL-P0-025`, `AVL-P0-026`, `AVL-P0-027`, `AVL-P0-030`, and `AVL-P0-032` remain `Proof remaining`.
- `AVL-P0-012` is also `Proof remaining`; targeted tamper evidence is green on:
  - `swift test --filter AuditTamperEvidenceTests`
  - `swift test --filter DatabaseManagerFileResolutionTests`
  - `swift test --filter AuditRepositoryTests`
  - `swift test --filter SchemaDriftTests`
- None of those items may move to `Manual acceptance remaining` until relevant full-suite proof is rerun from the current worktree after any dependent changes.
