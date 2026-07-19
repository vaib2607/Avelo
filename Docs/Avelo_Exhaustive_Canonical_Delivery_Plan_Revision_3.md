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
| AVL-P1-037 Day Book | ~~Implemented / automated proof~~; manual acceptance remaining | Durable drill/edit/cancel/return loop proven (H14–H17, see §7); GUI/visual acceptance open. |
| AVL-P2-011 Alt+2 duplicate | Implemented / proof remaining | Posted-flow lineage and fresh-number proof open. |
| AVL-P2-012 Ctrl+R recall | Implemented / proof remaining | Shortcut/privacy/context acceptance open. |
| AVL-P2-013 Ctrl+I/PgUp/PgDn | Partial | Selection/scroll/dirty/text-entry browse contract open. |
| Voucher PR1b dirty navigation | ~~Implemented / automated proof~~; manual acceptance remaining | Direct-replacement/nested-provider bypass audit in §6.7 and §7 H6/H7 closed; full interactive dirty-transition acceptance open. |
| Day Book shell | ~~Implemented / automated proof~~; manual acceptance remaining | H14–H17 durable loop (drill-in → edit/cancel/reverse → dirty gate → scope-preserving reload) proven at ViewModel/router level; GUI scroll/visual acceptance open. |
| Comparative prior-year columns | ~~Implemented / automated proof~~; manual acceptance remaining | Atomic publish fixed for Trial Balance/P&L (H18–H19, see §7); reconciliation to standalone runs already proven for all three report types. GUI acceptance open. |

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
through one pending intent. `AppRouterTests` and
`AppEnvironmentFlowTests.testDirtyEditorDefersCompanyOpenUntilDiscard`,
`testDirtyEditorDefersFinancialYearSwitchUntilDiscard`,
`testDirtyEditorDefersCompanyCloseUntilDiscard` prove Keep Editing, Discard,
one pending action (including repeated/distinct requests — first retained,
later rejected), capability-route retention, and company/FY/close deferral.
~~Direct-replacement audit beyond voucher paths: every non-voucher sheet's
self-dismiss (`router.presentedSheet = nil` on its own Cancel/Close) is
structurally safe — `presentedSheet` is a single optional, so no sheet can
replace another sheet's dirty editor.~~ ~~Nested-account provider lifecycle:
`NewVoucherSheet`'s isolated `accountCreationRouter` cannot observe or clear
the parent editor's pending navigation
(`testNestedAccountCreationRouterCannotObserveOrClearParentPendingNavigation`).~~
The full interactive dirty-transition matrix (keyboard/VoiceOver/visual)
remains mandatory. H7 is DONE for every enumerated `AppRouter`-owned
transition (see §7); H10/H11 retain their prior precise status, not broadened
here.

### 6.8 Voucher acceptance order

Unchanged: PR1b-close, shortcut acceptance and flush/post stability, then
item-cascade proof.

## 7. Daily browse and report interactions

Retain Revision 3 H1–H23 scorecard and contracts unchanged:

- ~~H1–H4: #9b, `ReportPeriodScope`, scoped validation, and own-FY comparative
  resolution.~~
- ~~H5 return-stack primitives, H8 provider wiring, H9 snapshots, H12 context
  shape, and H13 Day Book shell.~~
- ~~H6 company-switch dirty-order proof.~~ Traced every company-switch entry
  point (`openCompany`, `closeCompany`, `switchFinancialYear`) to confirm each
  routes through `AppRouter`'s single pending-intent gate before any mutation.
  Closed three previously-unproven gaps: company close was never proven
  dirty-gated (only clean close was tested); two distinct pending
  company-switch targets while dirty had no proof that only the first
  survives; and the discard path had no proof that stale `accountTree`/route/
  sheet state is rebuilt, not just `companyId`. Evidence:
  `testDirtyEditorDefersCompanyCloseUntilDiscard`,
  `testRepeatedCompanySwitchRequestsRetainOnlyTheFirstPendingIntent`,
  `testDiscardedCompanySwitchLeavesNoStaleAccountTreeOrRouteState`
  (`AppEnvironmentFlowTests`), `testSecondDistinctExternalContextRequestDoesNotReplaceFirst`
  (`AppRouterTests`). Repeated-request policy is reject-subsequent/retain-first,
  matching `AppRouter.requestNavigation`'s existing guard. No production code
  changed — the ordering was already correct; only the proof was missing.
- H7 dirty closure: ~~DONE for every enumerated `AppRouter`-owned transition~~
  (sheet dismissal, deep links, capability eviction, company open/close, FY
  switch, nested-account provider isolation). Window/app-lifecycle dirty
  closure is N/A — no such route exists in source. H10/H11 retain their prior
  precise status; not broadened by this work.
- ~~H14–H17 Day Book durable loop.~~ Audited row → drill-in → edit/cancel/
  reverse → dirty protection → return-to-scope → refresh: drill-in and
  Reverse both route through the single canonical `router.present` gate
  (`ReportsNavigation.openVoucher`); a successful edit/reverse calls
  `env.notifyDataChanged()`, which `ReportsView` observes to reload the
  current selection while reusing `selectedDay` rather than resetting it;
  stale row selection is cleared only when the selected voucher no longer
  appears in the reloaded rows. No bypass or second route found; no
  production code changed. Evidence:
  `testDayBookReloadPreservesSelectedDayAndValidSelection`,
  `testDayBookReloadClearsSelectionWhenVoucherNoLongerPresentForDay`
  (`ReportsViewModelTests`). Table row identity (`Voucher.ID`) is what SwiftUI
  relies on for scroll-position stability across the reload; that visual
  behavior is GUI-only and stays open.
- ~~H18–H19 atomic comparative.~~ Trial Balance and P&L previously assigned
  the primary column before attempting the comparative fetch: a comparative
  failure (e.g. a rescope whose prior-year window falls in a gap with no
  financial year) left the primary column silently advanced to the new scope
  while the comparative column kept its stale value from the previous scope —
  two mismatched periods rendered side by side. Fixed to compute both periods
  into locals and publish only together, matching Balance Sheet's existing
  #9b atomic-publish contract; on failure the entire prior snapshot now
  survives unchanged rather than partially updating. No other report type
  carries a comparative column, so this closes H18–H19 in full. Evidence:
  `testFailedComparativeRescopeLeavesEntireTrialBalanceSnapshotUnchanged`
  (`ReportsViewModelTests`); production change in
  `ReportsViewModel.reload()`'s `.trialBalance`/`.profitLoss` cases.
- H20–H21 zoom/restoration — **audited, not implemented; parked as a scoped
  follow-up feature, not a bug:**
  1. *Current state:* `AppRouter.browseReturnStack`/`pushBrowseReturnContext`/
     `popBrowseReturnContext` exist and are tested in isolation
     (`AppRouterTests`), but no UI report drill-down calls them.
     `ReportsBody+Navigation.openLedger(_:)` and other drill-ins overwrite
     `vm.selection`/scope and reload directly, destroying the prior report's
     scope/filters/selection with no push; no Back affordance exists anywhere.
  2. *Open design questions:* On return, what exactly must restore — report
     scope (company/FY/as-of)? Filters? Row selection? Scroll position, and if
     so keyed on what identity? How does generic return-stack ownership
     interact with Day Book's already-shipped H14–H17 scope-preservation loop
     (§7 above), which solves a narrower version of this same problem for one
     screen?
  3. *Future implementation outline:* wire `pushBrowseReturnContext` at every
     report drill-in entry point (account ledger, voucher drill, Day Book);
     add a Back/Return affordance bound to `popBrowseReturnContext` that
     restores scope/filters/selection per a documented contract; extend
     `ReportsViewModelTests` with drill → edit/cancel → return scenarios
     asserting restored context or a clearly documented adjustment.
- H22 docs and H23 manual matrix remain open as specified in Revision 3.

Manual/GUI acceptance still open for H6, H7, and H14–H17: keyboard/VoiceOver
traversal, visual scroll/selection behavior, and named accountant/operator
sign-off. Automated proof does not substitute for this.

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
