# Avelo — Exhaustive Canonical Delivery Plan, Revision 3

## Reconciled status — 2026-07-19

This is the editable working copy of the user-supplied Revision 3 plan. It
preserves its scope and order. Strike-through means source plus applicable
automated proof exists on the current dirty worktree; it never means human or
distribution acceptance.

### Design-first features vs proof gaps

Two different kinds of "open" appear throughout this document and must not be
conflated:

- **Proof gaps** — the architecture/behavior already exists and is correct;
  what's missing is a test or a small demonstrated-bug fix. This is the bulk
  of the work closed in §4, §6, and §7 (integrity/malformed-data/valuation
  matrices, H6/H7/H14–H19, Alt+2 fresh-number, Ctrl+R, Ctrl+I/PgUp/PgDn).
- **Design-first features** — the capability genuinely does not exist yet and
  requires a spike, a chosen design (command/memento history, multi-window
  state ownership, a period-configuration DSL, lineage schema), or domain
  input from accountants/operators before any code is safe to write. These
  are explicitly **not** bugs, not mislabeled proof gaps, and not silently
  scoped out — each is recorded with current state, why it's design-first,
  preconditions for resuming, and next steps, so it can be picked up as its
  own scoped session:
  - **Phase 4** (§8): AVL-P1-017 multi-window (registry/router/draft
    ownership spike required) and AVL-P1-025 undo/redo (command-history
    design required).
  - **Phase 5** (§10, §11–14): UOM discovery (needs accountant/operator input
    on real-world unit patterns before any schema work) and H22 canonical
    documentation (best done once the above designs settle, not before).
  - Three smaller design-first slices originally logged here have since been
    designed and closed: Alt+2 duplicate lineage tracking (§2, AVL-P2-011)
    via `MigrationV031` (additive, self-referencing, follows the existing
    `cancellation_voucher_id` pattern exactly); the comparative-period-
    configuration DSL (§2, AVL-P1-036) via `ComparativePeriod` (pure
    date-shift value type, no schema/service-layer change, default
    preserves prior behavior exactly); and H20–H21 zoom/restoration (§7) via
    `ReportsNavigation.openLedger`/`returnToPreviousReport`, wiring the
    already-existing `AppRouter` return-stack primitives once the actual
    blast radius (only `openLedger`, not every drill-in) was traced. None
    were a cross-cutting redesign once actually scoped.

  Parking one of these is not the same as closing it — none of the above may
  be marked DONE from a future proof-only pass; each requires its own design
  decision first.

### Acceptance and documentation remain separate gates

Automated proof — however thorough — is never a substitute for named
accountant/operator acceptance, keyboard/VoiceOver/accessibility traversal,
visual/scroll/selection behavior on real hardware, PDF/print output
verification, or canonical documentation reflecting final shipped behavior.
Every §2 table row and every struck item in §4–§7 that still lists "manual
acceptance remaining" stays open until that acceptance is actually performed
and recorded (tester, date, build/SHA, steps, pass/fail) — not inferred from
green tests. See §3 for the current release-evidence gate list.

## 1. Operating rules

Keep the original authority order, offline/SQLCipher/checked-money contracts,
dirty-worktree discipline, and PR proof requirements unchanged. Any status
flip requires path or test evidence in Status, Execution, and Release Board.

## 2. Current audited status

| Area | Reconciled state | Evidence / remaining work |
| --- | --- | --- |
| #9b Balance Sheet | ~~DONE~~ | Scoped immutable `BalanceSheetScope`, selected-FY integrity/activity reconciliation, atomic comparison publication, same-company FY reset, automated proof, and bundled/accountant acceptance are complete. `BalanceSheetReconciliationTests` 10/0 and `ReportsViewModelTests` 14/0. |
| #10 item-invoice default | ~~Implemented / automated proof~~; manual acceptance remaining | `VoucherEditViewModel`, `NewVoucherSheet`, draft tests; GUI/keyboard acceptance open. |
| V027 dual track | Partial / proof remaining | Sections 4.1–4.6 landed below; integrity matrix, malformed persisted-data matrix, staged-rollback matrix (4/5 stages), stock valuation parity, reversal parity (both paths), and GST Summary parity all proven (§4.4/§4.6/§4.7). Remaining: broader historic reversal fixtures, report/export parity for Outstanding/Cash Flow/Stock Ageing/PDF export, and manual acceptance. |
| AVL-P0-020 keyboard baseline | ~~Implemented / automated proof~~; manual acceptance remaining | GUI traversal and VoiceOver acceptance open. |
| AVL-P0-033 inventory capability | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant capability-toggle acceptance open. |
| AVL-P0-034 mutation audit | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant audit-diff acceptance open. |
| AVL-P0-035 automatic inventory modes | ~~Implemented / automated proof~~; manual acceptance remaining | Accountant workflow acceptance open. |
| AVL-P0-036 legacy restore remapping | ~~Implemented / automated proof~~; operator acceptance remaining | Operator restore acceptance open. |
| AVL-P1-017 multi-window | Proof remaining | Registry consistency spike, editor/draft/window acceptance open. |
| AVL-P1-025 undo/redo | Missing | Full design and implementation open. |
| AVL-P1-026 Alt+C | ~~Implemented / automated proof~~; manual acceptance remaining | Focus return/audit GUI proof open. |
| AVL-P1-036 comparative reports | ~~Atomic publish~~; ~~period configuration~~ | Atomic publish closed via §7 H18–H19 fix. **Period configuration closed**: `ComparativePeriod` (priorYear/priorMonth/priorQuarter/custom(monthsBack:)) replaces the hardcoded `priorYear()`, used identically by Trial Balance/P&L/Balance Sheet via `ReportsViewModel.comparativePeriod` (default `.priorYear`, bit-for-bit preserves prior behavior). No `ReportService` changes — the DSL only decides which date to ask for. `comparisonPeriods[]` from the original spec was scoped to a single `Optional` value: the UI renders exactly one comparative column per report today, a real array would be dead plumbing; documented as a non-breaking future extension. Evidence: `ComparativePeriodTests`, `ReportsViewModelTests` (priorMonth/priorQuarter reconciliation + atomic-publish-under-non-default-mode). GUI mode-picker not built (task scoped this as internal/labels-only); GUI acceptance open. |
| AVL-P1-037 Day Book | ~~Implemented / automated proof~~; manual acceptance remaining | Durable drill/edit/cancel/return loop proven (H14–H17, see §7); GUI/visual acceptance open. |
| AVL-P2-011 Alt+2 duplicate | ~~Fresh-number proof~~; ~~lineage tracking~~ | Fresh/distinct number and id proven same-FY and cross-FY. **Lineage closed**: `Voucher.duplicatedFromVoucherId` (`MigrationV031`, additive/nullable, same pattern as `cancellation_voucher_id`) records the source voucher, set only by `VoucherEditViewModel.duplicateDraft`, threaded through `VoucherDraft`/`VoucherEntryDraft`/both `VoucherService` posting paths. Proven same-FY, cross-FY, non-duplicate-stays-nil, repeated-duplicate, Reverse/Cancel-non-inheritance, and the GST-round-off reconstruction hazard (`normalizedDraftForPosting` rebuilds `VoucherDraft` at two sites that must explicitly thread the field or it silently vanishes for round-off-eligible types). Evidence: `VoucherDraftTests`, `VoucherServiceTests`. No UI surfacing (not requested); GUI/keyboard acceptance still open. |
| AVL-P2-012 Ctrl+R recall | ~~Implemented / automated proof~~; manual acceptance remaining | Company-scope privacy (`testRecentNarrationsIsScopedToCompany`), distinct/most-recent-first ordering, limit, and Narration-only focus eligibility (S3, `KeyboardShortcutMapTests`) all proven. No cross-user boundary applies — single-operator per-company local database, no user/session concept exists. FY-scoping is intentionally absent (recall spans company history, standard Tally behavior), not a gap. Keyboard/VoiceOver acceptance open. |
| AVL-P2-013 Ctrl+I/PgUp/PgDn | ~~Implemented / automated proof~~; manual acceptance remaining | Selection movement and boundary clamping fully proven (`testSelectNextAndPreviousMoveThroughLoadedPageWithoutTouchingFilterState`, `testSelectNextAtLastRowIsANoOp`). Ctrl+I structurally cannot mutate list/filter/selection state — its handler never references the list view model, only routes through `AppActionRegistry.perform` to open a fresh journal sheet. Dirty-state cooperation is inherent via the existing focus-scoped `.onKeyPress` (fires only when the voucher table owns focus, never during text entry). Keyboard/VoiceOver acceptance open. |
| Voucher PR1b dirty navigation | ~~Implemented / automated proof~~; manual acceptance remaining | Direct-replacement/nested-provider bypass audit in §6.7 and §7 H6/H7 closed; full interactive dirty-transition acceptance open. |
| Day Book shell | ~~Implemented / automated proof~~; manual acceptance remaining | H14–H17 durable loop (drill-in → edit/cancel/reverse → dirty gate → scope-preserving reload) proven at ViewModel/router level; GUI scroll/visual acceptance open. |
| Comparative prior-year columns | ~~Implemented / automated proof~~; manual acceptance remaining | Atomic publish fixed for Trial Balance/P&L (H18–H19, see §7); reconciliation to standalone runs already proven for all three report types. GUI acceptance open. |

## 3. Reconciliation and release evidence

~~`make test` (610/610, 8 skipped), `make rule-audit` (net-check/R-16/R-15/
R-4/docs-check all PASS), `make rc-local`, bundle validation, bundle
self-test, and `make launch-smoke` all re-run and passed on final SHA
`28ac559` (2026-07-20).~~ `rg` (ripgrep 15.2.0) installed via `brew install
ripgrep`, closing the previous `docs-check` environment gap — no code or
docs changed to work around it, the gate now genuinely passes. New bundle
executable SHA-256: `199cd363e37e7bfe9d61f2427f2fa829e030b94940cafea8a8d99b7628469d62`
(supersedes the stale fee084f-era `25a702c5...` value). Note:
`Scripts/launch_smoke.sh` re-runs `validate_bundle.sh` + `bundle_selftest.sh`
non-interactively — it does not actually open a GUI window, so "Launch smoke
OK" here is not the same as confirming the bundled app opens cleanly on a
real Mac; that still needs the manual GUI run the script's own output names.

Still required: named accountant, operator, keyboard/accessibility/visual/PDF/
print acceptance; distribution-channel decision; Developer ID, hardened runtime,
notarization, stapling, Gatekeeper, and clean-Mac install/upgrade proof; an
actual GUI launch of the bundle (not just the non-interactive self-test).

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

~~Direct integrity matrix:~~ cross-company ownership trigger for
`trn_inventory_cost_allocations` (previously only `trn_accounting`/
`trn_inventory` inserts had direct coverage), CHECK constraints
(`amount_paise > 0`, `debit_or_credit` enum, `quantity_numerator/denominator
> 0`, `movement_type` enum), and `UNIQUE(voucher_id, line_order)` all proven
with happy/negative-path pairs. Evidence: `CanonicalIntegrityMatrixTests`
(6/0).

~~Malformed persisted-data matrix (legacy schema boundary):~~ cross-company
legacy ledger line, duplicate legacy ledger-line id, and negative legacy
stock-movement quantity all traced to fail closed at the V026 legacy
schema's own triggers/PRIMARY KEY/CHECK constraints — structurally
impossible to persist, so migration never sees them; stronger guarantee
than a migration-time check. Evidence: `V027MigrationParityTests`
(`testCrossCompanyLegacyLedgerLineFailsClosedAtLegacySchema`,
`testDuplicateLegacyLedgerLineIdFailsClosedAtLegacySchema`,
`testNegativeLegacyStockMovementQuantityFailsClosedAtLegacySchema`).

~~Staged-rollback matrix (4 of 5 stages):~~ validation, accounting, inventory,
and audit-write stages each proven to leave zero row-count delta across
`avelo_vouchers`/`trn_accounting`/`trn_inventory`/
`trn_inventory_cost_allocations`/`avelo_audit_events`. Accounting and
audit-write stages use an injected temporary SQLite trigger to force failure
precisely inside the transaction (same technique as
`InventoryCostAllocationServiceTests
.testAuditFailureRollsBackAllocationAndLandedValue`), since no natural
validation predicate reaches that deep. Evidence: `ItemInvoiceServiceTests`
(`testValidationStageFailureLeavesNoPartialWriteAcrossAnyTable`,
`testAccountingStageFailureLeavesNoPartialWriteAcrossAnyTable`,
`testInventoryStageFailureLeavesNoPartialWriteAcrossAnyTable`,
`testAuditWriteStageFailureLeavesNoPartialWriteAcrossAnyTable`). The
**allocation** stage doesn't belong to this pipeline at all —
`ItemInvoiceService.post()` never calls `InventoryCostAllocationService`
inline (allocation is posted separately, after the voucher exists) — and is
already proven by that service's own tests:
`testAllocationRejectsRecoverableGSTSourceAndLeavesTargetsUntouched`
(validation-stage) and `testAuditFailureRollsBackAllocationAndLandedValue`
(audit-write-stage).

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

~~Stock valuation output parity:~~ FIFO and weighted-average items' closing
quantity/value reconcile against an independent raw SQL sum over
`trn_inventory` — the same authoritative-SQL-vs-live pattern already used
for trial balance (`AccountTreeReconciliationTests`) and P&L
(`ProfitLossReconciliationTests`), extended to inventory. Proves
canonical-track reads aren't dropping/double-counting movements post
migration, without re-deriving FIFO/weighted-average layer logic. Evidence:
`StockValuationReconciliationTests` (2/0). Day Book already reads the
canonical `trn_accounting_compat` view directly with existing behavioral
tests; no separate parity harness was needed there.

~~Reversal parity:~~ both reversal code paths proven to net the canonical
tracks to zero — plain-voucher reversal (`VoucherService.reverse`) nets
`trn_accounting` per ledger account; item-invoice reversal
(`ItemInvoiceService.reverse`) nets both `trn_accounting` per account and
`trn_inventory` net quantity per item. Evidence:
`ReversalReconciliationTests.testPlainVoucherReversalNetsAccountingTrackToZero`,
`ItemInvoiceServiceTests.testItemInvoiceReversalNetsCanonicalTracksToZero`.

~~GST Summary report parity:~~ `ReportService.gstSummary`'s output/input tax
totals reconcile against a raw SQL sum over `trn_accounting`, using direct
journal postings to isolate the report's own aggregation from
`ItemInvoiceService`'s GST computation (covered separately). Evidence:
`GSTSummaryReconciliationTests.testGstSummaryOutputAndInputTaxReconcileToRawLedgerSums`.

Remaining proof: broader historic reversal fixtures (multi-line, partial,
cross-FY reversal scenarios beyond the two proven cases) and report/export
canonical parity for report types still uncovered — Outstanding, Cash Flow,
Stock Ageing, and Invoice PDF export have no reconciliation harness.

### 4.7 V027 exit

Completed automated slices:

- ~~fresh canonical schema, locations, draft persistence, canonical posting,
  locks, allocation, partial return, reverse/cancel, migration failure, and
  restore/remap proof.~~
- ~~current `make test`, `make rule-audit`, `make rc-local`, bundle validation,
  self-test, and launch smoke.~~
- ~~direct integrity matrix and malformed persisted-data matrix~~ (§4.4).
- ~~FIFO/weighted-average stock valuation canonical parity~~ (§4.6).
- ~~staged-rollback matrix, 4 of 5 stages:~~ validation, accounting,
  inventory, and audit-write stages all leave row counts unchanged across
  `avelo_vouchers`, `trn_accounting`, `trn_inventory`,
  `trn_inventory_cost_allocations`, and `avelo_audit_events` — empirically
  proving the single outer re-entrant transaction claim rather than only
  asserting the thrown error type. The allocation stage is proven separately
  by `InventoryCostAllocationServiceTests` since it isn't part of this
  pipeline. Evidence: `ItemInvoiceServiceTests`
  (`testValidationStageFailureLeavesNoPartialWriteAcrossAnyTable`,
  `testAccountingStageFailureLeavesNoPartialWriteAcrossAnyTable`,
  `testInventoryStageFailureLeavesNoPartialWriteAcrossAnyTable`,
  `testAuditWriteStageFailureLeavesNoPartialWriteAcrossAnyTable`).
- ~~reversal canonical parity~~ (plain-voucher and item-invoice paths) and
  ~~GST Summary report parity~~ — see §4.6.

Open before V027 release-ready:

- broader historic reversal fixtures (multi-line/partial/cross-FY, beyond
  the two proven single-item cases) and report/export canonical parity for
  Outstanding, Cash Flow, Stock Ageing, and Invoice PDF export;
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
Focused evidence: `VoucherDraftTests` 45/0, `AppRouterTests` 13/0,
`AppEnvironmentFlowTests` 18/0, and `KeyboardShortcutMapTests` 9/0
(counts grown since the original 2026-07-19 pass as H6/S9/S11/§6.7 proof was
added — see §7 and §6.7 below); `make test` (604/604) and `git diff --check`
passed on the active worktree. `make rule-audit` blocked only on missing
`rg` (§3). Bundle validation/bundle self-test/launch smoke are from the
original fee084f-era pass and have not been re-run since; those never
replace the required interactive keyboard/VoiceOver acceptance regardless.

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
- ~~H20–H21 zoom/restoration.~~ Tracing every drill-in call site found the
  blast radius was narrower than the original audit assumed: `openVoucher`
  (used by Day Book, Outstanding, Inventory movements, and Financial
  Statements' own voucher links) already round-trips correctly — it's a
  modal sheet over the unchanged report, and dismiss-triggered `reload()`
  reuses the same selection/scope. Only `openLedger` actually destroyed
  context. Since `asOf`/`fromDate`/`toDate`/`fyId` are never touched by a
  ledger drill (same `ReportsViewModel` instance, only `.selection`/
  `.ledgerAccountId` change), the restoration contract is narrow: push/
  restore which report was showing, nothing else — no scope, filters, or
  row selection exists to lose. `ReportsNavigation.openLedger`/
  `returnToPreviousReport` (`Avelo/Features/Reports/ReportsView+Content.swift`)
  wire `AppRouter`'s existing `pushBrowseReturnContext`/
  `popBrowseReturnContext`/`BrowseSurface.report` primitives — no `AppRouter`
  changes needed. A cross-company/FY stale-context guard discards rather
  than applies a mismatched pop (a company/FY switch isn't blocked by any
  dirty-gate while a ledger drill is open). A conditional "Back to X"
  affordance sits next to the existing Reports breadcrumb, rendering only
  when the stack is non-empty. Day Book's H14–H17 loop is untouched — Day
  Book has no `openLedger` call site at all. Scroll-position restoration
  remains an explicit, documented limitation (no such infrastructure exists
  anywhere in this codebase, matching Day Book's own open item — not
  fabricated here). Evidence: `ReportsViewModelTests`
  (`testOpenLedgerPushesReturnContextAndRestoresPriorSelectionOnBack`,
  `testRepeatedDrillsProduceCorrectLIFOReturnOrder`,
  `testReturnContextFromDifferentCompanyIsDiscardedNotApplied`,
  `testDrillEditVoucherReturnPreservesSelectionWithoutStackInvolvement`).
  GUI acceptance (visual Back-button behavior, scroll) remains open.
- H22 docs and H23 manual matrix remain open as specified in Revision 3.

Manual/GUI acceptance still open for H6, H7, and H14–H17: keyboard/VoiceOver
traversal, visual scroll/selection behavior, and named accountant/operator
sign-off. Automated proof does not substitute for this.

PR2b, PR3b, PR4, and PR5 requirements, prerequisites, test matrices, and exit
criteria remain unchanged and unstruck.

## 8. Multi-window and undo/redo (deferred — design-first, not close-a-gap)

Unchanged and open. `AVL-P1-017 Registry Connection Consistency Spike` must
close before GUI multi-window expansion. `AVL-P1-025` undo/redo remains missing.

**Current state:**

- ~~AVL-P1-017 multi-window spike/design.~~ Traced the actual window wiring
  (not assumed): `AppEnvironment`/`AppRouter`/`KeyboardBridge` are created
  once in `AveloApp.init()` and shared by any window SwiftUI's default
  `WindowGroup` spawns — a company switch or dirty edit in one window would
  today silently affect a second window, since nothing currently prevents
  macOS from giving the user one. `DatabaseManager` is already an `actor`
  with `openHandles: [Company.ID: CompanyHandle]`, already idempotent on
  `openCompany(id:)` — the DB connection layer is closer to
  multi-window-ready than assumed. Two real, concrete conflicts found:
  `DatabaseManager.closeCompany(id:)` has no reference counting (closing a
  company in one window would close the shared connection out from under a
  sibling window on the same company), and no lock/lease exists to prevent
  the same posted voucher being opened for edit in two windows at once
  (last-write-wins today, single-window-only-reachable; multi-window makes
  it reachable via two windows instead of two rapid saves, but doesn't
  introduce a new category of risk). Full ownership design (per-window
  `AppRouter`/`WindowCompanyContext` vs shared `DatabaseManager`/
  `KeyboardMonitor`), architecture-change outline, and test strategy are
  recorded in full in the session transcript that produced this update —
  design deliverable complete; **implementation not started**, by this
  session's own explicit scope (design/spike only, no code).
- AVL-P1-025 undo/redo: no command/memento/history implementation exists;
  editor actions apply directly to state with no reversible stack.

**Nature of work:** explicitly design-first feature work, not close-a-gap
proof. Multi-window requires a spike observing real GUI/editor behavior to
define ownership of registry, router, and draft lifecycles across windows.
Undo/redo requires choosing and designing a history model (command vs
memento) integrated into voucher/editor flows with well-defined user
expectations. Both cut across business/ViewModel/GUI layers and cannot be
safely reduced to "add tests and tweak an ordering bug."

**Preconditions for resuming:** dedicated design sessions to run the
multi-window registry consistency spike with realistic scenarios (multiple
windows editing drafts, navigating reports, posting), and to select/sketch an
undo/redo design (likely command-based) with clear scope — which actions are
undoable, per-session limits, how dirty state interacts with history. Updated
technical notes must capture desired invariants (no double-edit of the same
draft across windows, undo/redo only the user's own actions, bounded history
per session) and impact on existing contracts (dirty routing, Day Book loop,
V027 posting).

**Next steps when picked up:**

- AVL-P1-017: design is complete (see above). Implementation session should:
  split `AppEnvironment` into a slim app-wide object (backup service,
  registry, `DatabaseManager` reference) and a per-window
  `WindowCompanyContext` (company/FY/database/featureSet/cache); move
  `AppRouter`/`KeyboardBridge` construction from `AveloApp.init()` into the
  per-window scene builder (`AppRouter` already needs no internal changes —
  `AppRouterTests` already constructs bare instances freely); add
  reference-counting to `DatabaseManager.closeCompany(id:)`; teach
  `KeyboardMonitor.shared` to route to the key window's bridge instead of
  one captured bridge; add the test suite outlined in the design (window-
  scoped router independence, ref-counted close, same-company two-window
  edit sequence, cross-window data-change notification, full regression
  pass on every existing reconciliation harness). No schema/migration
  needed for any of this.
- AVL-P1-025: implement command/history model for voucher/editor; add tests
  covering undo/redo correctness, history limits, and interaction with
  posting/draft validation.

## 9. P0 blockers

~~AVL-P0-020, AVL-P0-033, AVL-P0-034, AVL-P0-035, and AVL-P0-036 automated
implementation/proof landed.~~ Their named manual acceptance requirements stay
open exactly as Revision 3 specifies.

## 10. Units of measure (deferred — domain discovery required)

Discovery required before broader UOM work. No implicit base-unit calculation.

**Current state:** no broader UOM implementation exists; plan explicitly
states discovery is required before broader UOM work and forbids implicit
base-unit calculation.

**Nature of work:** domain and design-first work requiring human input. UOM
discovery requires accountants/operators to enumerate real UOM patterns
(boxes vs pieces, kg vs g, packs vs units) and constraints — this cannot be
done as a purely technical proof slice.

**Preconditions for resuming:** scheduled domain discovery sessions with
accountants/operators to collect UOM use cases, allowable conversions, and
accounting expectations; decide explicit vs implicit conversion rules and how
inventory valuation should treat UOM.

**Next steps when picked up:** turn discovery into a concrete UOM spec
(schema implications, validation rules, posting interaction); implement
minimal safe UOM support consistent with that spec and V027.

## 11–14. Phase 1-A, Phase 1-B, Phase 1-C, Phase 2

All listed later backlog remains open in Revision 3 order. Do not infer closure
from models, routes, migrations, or compatibility adapters.

### H22 docs and backlog ordering (deferred)

**Current state:** documentation and the Phase 1-A/B/C/2 backlog remain open
and unstruck; behavior is still evolving and must be captured canonically
once designs settle.

**Nature of work:** best done once key behaviors (V027 parity, Day Book loop,
comparative reports, shortcuts, undo/redo, multi-window) are stable, so docs
reflect final contracts rather than a moving target.

**Next steps when picked up:** update canonical docs to reflect final
behaviors; keep the Phase 1-A/B/C/2 backlog aligned with actual
implementation status.

## 15. Binding execution order

Unchanged, except V027 automated implementation/proof may proceed in parallel
with PR1b-close. PR2b still depends on PR1b-close, not V027 accountant signoff.

## Final release condition

Unchanged: no P0 blocker, settled proof, migration/restore/benchmark/bundle
evidence, all named accountant/operator/keyboard/accessibility/visual/PDF/print
acceptance, distribution gates, and aligned canonical documentation.
