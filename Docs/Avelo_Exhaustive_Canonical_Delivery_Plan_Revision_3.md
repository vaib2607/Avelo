# Avelo — Exhaustive Canonical Delivery Plan, Revision 3

## Reconciled status — 2026-07-19

This is the editable working copy of the user-supplied Revision 3 plan. It
preserves its scope and order. Strike-through means source plus applicable
automated proof exists on the current dirty worktree; it never means human or
distribution acceptance.

## 1. Operating rules

Keep the original authority order, offline/SQLCipher/checked-money contracts,
dirty-worktree discipline, and PR proof requirements unchanged. Any status
flip requires path or test evidence in Status, Execution, and Release Board.

## 2. Current audited status

| Area | Reconciled state | Evidence / remaining work |
| --- | --- | --- |
| #9b Balance Sheet | ~~DONE~~ | Scoped immutable `BalanceSheetScope`, selected-FY integrity/activity reconciliation, atomic comparison publication, same-company FY reset, automated proof, and bundled/accountant acceptance are complete. `BalanceSheetReconciliationTests` 10/0 and `ReportsViewModelTests` 14/0. |
| #10 item-invoice default | ~~Implemented / automated proof~~; manual acceptance remaining | `VoucherEditViewModel`, `NewVoucherSheet`, draft tests; GUI/keyboard acceptance open. |
| V027 dual track | Partial / proof remaining | Sections 4.1–4.6 landed below; remaining parity matrices and manual acceptance remain. |
| AVL-P0-020 keyboard baseline | ~~Implemented / automated proof~~; manual acceptance remaining | GUI traversal and VoiceOver acceptance open. |
| AVL-P0-033 inventory capability | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant capability-toggle acceptance open. |
| AVL-P0-034 mutation audit | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant audit-diff acceptance open. |
| AVL-P0-035 automatic inventory modes | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant workflow acceptance open. |
| AVL-P0-036 legacy restore remapping | ~~Implemented / automated proof~~; operator acceptance remaining | Operator restore acceptance open. |
| AVL-P1-017 multi-window | Proof remaining | Registry consistency spike, editor/draft/window acceptance open. |
| AVL-P1-025 undo/redo | Missing | Full design and implementation open. |
| AVL-P1-026 Alt+C | ~~Implemented / automated proof~~; manual acceptance remaining | Focus return/audit GUI proof open. |
| AVL-P1-036 comparative reports | Partial | Atomic publish, general period configuration, acceptance open. |
| AVL-P1-037 Day Book | Partial | Durable drill/edit/cancel/return loop open. |
| AVL-P2-011 Alt+2 duplicate | Implemented / proof remaining | Posted-flow lineage and fresh-number proof open. |
| AVL-P2-012 Ctrl+R recall | Implemented / proof remaining | Shortcut/privacy/context acceptance open. |
| AVL-P2-013 Ctrl+I/PgUp/PgDn | Partial | Selection/scroll/dirty/text-entry browse contract open. |
| Voucher PR1b dirty navigation | Partial | Remaining bypass audit in §6.7 open. |
| Day Book shell | Implemented | Durable return/state/action work open. |
| Comparative prior-year columns | Implemented | Atomicity/reconciliation completion open. |

## 3. Reconciliation and release evidence

~~`make test`, `make rule-audit`, `make rc-local`, bundle validation/self-test,
and `make launch-smoke` passed on the current worktree.~~ Current bundle
executable SHA-256:
`25a702c569d0fcfbe0986d6ff5da18499a6e36abf10b162f3f70bc94aa22e8ec`.

Still required: named accountant, operator, keyboard/accessibility/visual/PDF/
print acceptance; distribution-channel decision; Developer ID, hardened runtime,
notarization, stapling, Gatekeeper, and clean-Mac install/upgrade proof.

## 4. V027 — dual-track accounting and inventory

### 4.1 Fixed naming and canonical tracks

~~Retain `avelo_accounts`, `avelo_inventory_items`, and `avelo_vouchers`; add
`trn_accounting`, `trn_inventory`, `trn_inventory_cost_allocations`, and
`avelo_inventory_locations`; retain legacy forensic compatibility adapters and
do not dual-write.~~

Evidence: `MigrationV027`, canonical repositories, compatibility views,
`SchemaVersion.current == .v30`.

### 4.2 Model contracts

~~Immutable voucher header; canonical accounting/inventory models;
`VoucherDraft.EntryMode`; `VoucherItemLine` exact quantities; canonical
`StockMovement` location/evidence/reversal/base/landed fields; fresh eligible
Sales/Purchase item mode; recovery/edit mode preservation.~~

Evidence: `VoucherDraft`, `VoucherItemLine`, `StockMovement`,
`VoucherDraftTests`, `VoucherDraftRepositoryTests`.

### 4.3 Posting ownership

~~`VoucherRepository` writes headers only, `LedgerLineRepository` canonical
accounting only, `InventoryRepository` canonical inventory only, and
`ItemInvoiceService` owns one re-entrant outer transaction.~~

~~Canonical posting order: validate; locked revalidate; header; accounting;
invoice evidence; inventory; optional allocations; one audit; commit; cache/UI
publication after commit.~~

Evidence: `VoucherService.postInCurrentTransaction`, `ItemInvoiceService`,
`InventoryService.recordMovementInCurrentTransaction`,
`ItemInvoiceServiceTests`, `AuditMutationContractTests`.

### 4.4 Validation and integrity

~~Typed service validation and canonical same-company/FY-lock triggers landed.~~
~~Malformed legacy canonical IDs and unbalanced V026 data fail closed during
migration.~~

Remaining proof: full direct foreign-key/CHECK/trigger matrix, every staged
composite failure boundary, and complete malformed persisted-data matrix.

### 4.5 Inventory policy

~~One active `MAIN`/`Main` location per company, explicit audited freight and
irrecoverable-tax allocations, deterministic exact-quantity residual-paise
allocation, recoverable-GST rejection, and service-only partial Debit/Credit
Note returns with immutable source lineage landed.~~

Evidence: `MigrationV027`, `MigrationV030`,
`InventoryCostAllocationService`, `ItemInvoiceReturnService`,
`InventoryCostAllocationServiceTests`, `ItemInvoiceReturnServiceTests`.

Multi-godown/transit UI remains deferred. Fractional item invoices remain
explicitly deferred; standalone exact-UOM inventory remains supported.

### 4.6 Migration

~~V027 schema/backfill/compatibility views, V028 draft recovery, V029 locks,
and V030 allocation/return audit actions are forward-only migrations.~~
~~Populated V026 upgrade fixture, unbalanced/malformed-ID failure rollback, and
canonical restore/remap fixture landed.~~

Evidence: `V027MigrationParityTests`,
`RestoreServiceTests/testRestorePreservesCanonicalTracksAndAllocationLinks`.

Remaining proof: broader historic reversal/cross-company/failure fixtures and
full valuation/output parity.

### 4.7 V027 exit

Completed automated slices:

- ~~fresh canonical schema, locations, draft persistence, canonical posting,
  locks, allocation, partial return, reverse/cancel, migration failure, and
  restore/remap proof.~~
- ~~current `make test`, `make rule-audit`, `make rc-local`, bundle validation,
  self-test, and launch smoke.~~

Open before V027 release-ready:

- direct integrity and staged rollback matrices;
- FIFO/weighted-average, reversal, report/export canonical parity;
- named accountant/operator acceptance;
- item-invoice default bundled GUI acceptance.

## 5. Balance Sheet #9b

~~Company + selected FY + selected as-of scope; typed scope errors; one load
pipeline; strict loading/error/empty/table rendering; no false empty success;
comparative validation; documented opening rules.~~ Selected-FY integrity is
checked before as-of filtering, candidate construction uses one read transaction,
and same-company FY changes reset the owned scope without recreating the model.

Evidence: `ReportService.balanceSheet`, `ReportsViewModel`,
`BalanceSheetReconciliationTests`, `ReportsViewModelTests`.

~~Bundled macOS behavior and accountant acceptance.~~

Status: **DONE** — scoped reconciliation, atomic comparison, same-company FY
reset, bundle validation, and #9b manual acceptance were completed and
confirmed on 2026-07-19.

## 6. Voucher redesign and shortcut program

### 6.1–6.5 Layout, flush, focus, item cascade, default

~~Item-invoice default contract in §6.5 landed.~~

**PARTIAL — current implementation evidence:**
`VoucherEditorSubmission` is now the sole create/edit service command;
`VoucherEditViewModel` owns re-entry state, local typed errors, and
pre-submission validation; both sheets flush registered custom fields before
the command. Narration now uses `TextEditor`, so plain Return remains native
newline input, while the action bar preserves Command-Return. Both sheets use
the shared focus vocabulary and show local inline failure context. Ledger and
item cascades are model-owned, and item completion uses the exact posting
predicate (including zero-rate validity and one trailing blank-row reuse).
Focused evidence: `VoucherDraftTests` 44/0, `AppRouterTests` 11/0,
`AppEnvironmentFlowTests` 15/0, and `KeyboardShortcutMapTests` 7/0;
`make test`, `make rule-audit`, and
`git diff --check` passed on the active worktree on 2026-07-19. The local
bundle validation, bundle self-test, and launch smoke also passed; those do
not replace the required interactive keyboard/VoiceOver acceptance.

The item picker now provides focused searchable selection and an explicit
commit callback. Still open: full create/edit focus and cascade UI matrix,
and bundled keyboard/VoiceOver/visual acceptance.

### 6.6 Shortcut contracts

**PARTIAL — current implementation evidence:** Alt+C remains limited to the
focused eligible `AccountPicker`; Ctrl+V is limited to a fresh eligible
Sales/Purchase draft (never recovery or text editing) and Ctrl+R is Narration
only; Ctrl+I, Alt+2, PgUp, and PgDn
are now registered only on the focused voucher table, replacing hidden global
shortcut buttons. `VoucherShortcutContract` is the help-text source for
editor/table commands. Context/collision/manual acceptance proof remains open.

### 6.7 PR1b-close

**PARTIAL — current implementation evidence:** `AppRouter` now dirty-gates
ledger/report deep links, capability eviction, root sheet-binding dismissal,
financial-year switching, company open/close, and post-success dismissal
through one pending intent. `AppRouterTests` 11/0 and
`AppEnvironmentFlowTests.testDirtyEditorDefersCompanyOpenUntilDiscard` and
`testDirtyEditorDefersFinancialYearSwitchUntilDiscard` prove Keep Editing,
Discard, one pending action, capability-route retention, and company/FY
deferral. The direct-replacement audit beyond voucher paths,
nested-account provider lifecycle acceptance, and the full dirty-transition
matrix remain mandatory. H7/H10/H11 remain open.

### 6.8 Voucher acceptance order

Unchanged: PR1b-close, shortcut acceptance and flush/post stability, then
item-cascade proof.

## 7. Daily browse and report interactions

Retain Revision 3 H1–H23 scorecard and contracts unchanged:

- ~~H1–H4: #9b, `ReportPeriodScope`, scoped validation, and own-FY comparative
  resolution.~~
- ~~H5 return-stack primitives, H8 provider wiring, H9 snapshots, H12 context
  shape, and H13 Day Book shell.~~
- H6 company-switch dirty-order proof, H7/H10/H11 dirty closure, H14–H17 Day
  Book durable loop, H18–H19 atomic comparative, H20–H21 zoom/restoration,
  H22 docs, and H23 manual matrix remain open as specified in Revision 3.

PR2b, PR3b, PR4, and PR5 requirements, prerequisites, test matrices, and exit
criteria remain unchanged and unstruck.

## 8. Multi-window and undo/redo

Unchanged and open. `AVL-P1-017 Registry Connection Consistency Spike` must
close before GUI multi-window expansion. `AVL-P1-025` undo/redo remains missing.

## 9. P0 blockers

~~AVL-P0-020, AVL-P0-033, AVL-P0-034, AVL-P0-035, and AVL-P0-036 automated
implementation/proof landed.~~ Their named manual acceptance requirements stay
open exactly as Revision 3 specifies.

## 10. Units of measure

Discovery required before broader UOM work. No implicit base-unit calculation.

## 11–14. Phase 1-A, Phase 1-B, Phase 1-C, Phase 2

All listed later backlog remains open in Revision 3 order. Do not infer closure
from models, routes, migrations, or compatibility adapters.

## 15. Binding execution order

Unchanged, except V027 automated implementation/proof may proceed in parallel
with PR1b-close. PR2b still depends on PR1b-close, not V027 accountant signoff.

## Final release condition

Unchanged: no P0 blocker, settled proof, migration/restore/benchmark/bundle
evidence, all named accountant/operator/keyboard/accessibility/visual/PDF/print
acceptance, distribution gates, and aligned canonical documentation.
