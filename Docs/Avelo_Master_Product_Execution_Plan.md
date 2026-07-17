# Avelo Master Product and Execution Plan

## Authority

This is the single authoritative product roadmap and dependency-ordered execution plan for Avelo. It supersedes the old V2 execution draft, agent task boards, and disconnected Tally-parity roadmaps.

It does not replace the normative documents:

- `Avelo_Master_PRD.md` owns user-visible behavior.
- `Avelo_Rules.md` owns accounting, security, offline, and engineering invariants.
- `Avelo_Architecture.md` owns dependency and transaction boundaries.
- `Avelo_Schema.md`, executable migrations, and `SchemaVersion.current` own persistence.
- `Avelo_Release_Board.md` owns readiness and the release verdict.
- `Avelo_Execution_Checklist.md` owns the current executable queue.
- `Avelo_Status_Checklist.md` owns human-readable evidence and remaining acceptance.

Older narrative plans may be removed only after their unique requirements are represented here or in the correct normative document. Historical research remains archived for traceability.

## Product direction

Avelo is a native macOS accounting operating system combining:

```text
Native macOS shell
    + Tally-style accounting logic and keyboard rhythm
    + Avelo's checked, encrypted, offline, auditable accounting engine
    + No-code reports, charts, dashboards, documents, and workspaces
    + A later offline sandboxed Avelo Extension Language
```

Avelo will not pixel-clone legacy Tally. It will adopt its useful operating ideas:

- Every business object exposes contextual Create, Display, Alter, Configure, Duplicate, Print, Export, Drill Down, Reverse, Cancel, and Disable actions.
- Actions depend on company, financial year, feature flags, workspace, object state, and fiscal lock.
- Masters can be created inline without abandoning voucher entry.
- Reports are navigation surfaces that drill to ledgers, vouchers, bills, stock, bank lines, payroll, and audit events.
- Company capabilities and per-screen behavior are separate, equivalent to F11 and F12.
- One definition can drive views, fields, keyboard commands, menus, reports, charts, documents, and exports.
- SQLite remains the source of truth. Charts, saved reports, documents, and extensions cannot create competing financial truth.

## Locked decisions

- Fully offline, native macOS, initially single-user.
- SQLite/SQLCipher company databases remain authoritative and encrypted locally.
- No telemetry, runtime network access, remote updates, cloud KMS, government API calls, direct email dispatch, or runtime-loaded code.
- Tally business parity is phased: daily accounting first, then inventory, statutory, reports, documents, and advanced controls.
- No-code studios ship before the extension runtime.
- The later Avelo Extension Language provides TDL-equivalent business customization only through typed, approved, deterministic service APIs.
- Extensions cannot use arbitrary SQL, network, HTTP, sockets, COM, DLLs, subprocesses, shell commands, unrestricted files, or invariant bypasses.
- Direct distribution requires Developer ID signing, hardened runtime, notarization, stapling, clean-device installation, and upgrade proof.

## Current-state safety and progress notation

The formerly active Claude audit work is now settled into the current worktree. `MigrationV023` introduces the expanded audit taxonomy, `MigrationV024` adds company-owned party profiles, and `MigrationV025` adds dedicated cheque bounce/re-presentation actions without rewriting earlier migrations. The readable schema, naming freeze, restore remapping, and compatibility tests are synchronized through schema version 25.

Roadmap notation:

- `~~Struck through~~` means implementation and applicable automated proof passed on the identified worktree. It does **not** mean human acceptance or public-release readiness.
- `[OPEN — manual]` requires a named accountant, operator, accessibility, visual, or print tester using the artifact-bound protocol.
- `[OPEN — external]` requires credentials, hardware, another machine, or external platform state unavailable to the repository agent.
- `[PLANNED]` has not yet met its phase exit criteria.
- Evidence and readiness status remain authoritative in `Avelo_Release_Board.md`; this plan explains sequence and scope.

Current local candidate evidence, captured on 2026-07-17:

- ~~498 tests executed with 8 explicit skips and 0 failures.~~
- ~~Automated network, observation, placeholder, and money-path rule audit passed.~~
- ~~Warning-free production compilation passed with Swift warnings treated as errors.~~
- ~~RC bundle validation, backup/restore self-test, and GUI launch smoke passed.~~
- ~~Standard performance suite and explicit 500,000-voucher benchmark passed.~~
- ~~Bundle identity is centralized in `ReleaseVersion.env` as v1.1 build 3.~~
- [OPEN — manual] Accountant, operator, keyboard, VoiceOver, visual, PDF, and physical-printer acceptance in `Avelo_Phase0_Manual_Acceptance.md`.
- [OPEN — external] Developer ID signing, notarization, stapling, and clean-machine install/upgrade proof. The current artifact is ad-hoc signed and Gatekeeper-rejected.

## Architecture contracts

```text
SwiftUI/AppKit view
        ↓
@MainActor @Observable view model
        ↓
business service
        ↓
repository
        ↓
SQLite / SQLCipher
```

Every financial or operational mutation must enforce company ownership, financial-year resolution, fiscal locks, checked `Int64` paise and exact quantities, balanced postings, safe numbering, atomic audit, non-destructive correction, restore compatibility, and live report reconciliation.

### Central account eligibility

Account selection becomes a shared service, never view-local filtering.

```swift
enum AccountSelectionContext {
    case voucherParty(VoucherType.Code)
    case voucherPrimaryCashBank(VoucherType.Code)
    case voucherParticular(VoucherType.Code)
    case salesLedger
    case purchaseLedger
    case itemInvoiceParty(VoucherType.Code)
    case bankReconciliation
    case payrollExpense
    case payrollSettlement
    case orderParty(InventoryOrderType)
    case taxLedger(TaxLedgerRole)
    case stockAdjustment
    case costAllocation
    case unrestrictedPosting
}

struct AccountEligibility {
    let isEligible: Bool
    let rejectionReason: String?
    let ranking: Int
}

protocol AccountEligibilityEvaluating {
    func evaluate(
        account: Account,
        for context: AccountSelectionContext,
        company: Company,
        groups: [AccountGroup]
    ) -> AccountEligibility
}
```

Rules:

- Resolve full group ancestry, not only direct parent.
- Reject inactive, foreign-company, missing, and non-postable accounts.
- Cash/bank contexts accept descendants of Cash-in-Hand, Bank Accounts, and Bank OD.
- Sales and purchase contexts accept descendants of their respective groups.
- Party fields support customer, supplier, and dual-role parties with context ranking.
- Tax, stock, payroll, bank, cost, and order roles use explicit semantics.
- Never infer meaning from account-name or group-name substrings.
- A retained selection that becomes invalid remains visible with an explanation until replaced.
- The same policy serves picker, view model, service, import, edit, duplicate, restore validation, and tests.

Picker ranking is exact code, exact name, context preference, recent valid usage, hierarchy/name, then fuzzy search.

Account extensions use focused profile tables for aliases, party roles, credit limit, credit period, bill-wise policy, interest, bank/reconciliation, GST, tax, and mailing data. New tables require ownership, migration, restore, audit, and schema-drift coverage.

### Declarative definitions

Introduce shared definitions for `WorkspaceDefinition`, `CollectionDefinition`, `FieldDefinition`, `ActionDefinition`, `ReportDefinition`, `ChartDefinition`, `DocumentTemplateDefinition`, and `SavedWorkspaceConfiguration`.

Definitions control layout, typed data providers, fields, validation, visibility, focus order, capabilities, actions, report datasets, chart measures, document sections, and saved presentation settings. Financial calculations remain in typed services. Initial definitions are compiled Swift; user configuration stores only validated presentation metadata and stable references.

### Contextual action registry

Create one registry for menus, toolbar, action strip, command palette, row actions, deep links, shortcuts, help, and service authorization.

Core actions include Create, Display, Alter, Duplicate, Disable, Reverse, Cancel, Insert, Drill Down, Return, Change Period, Compare Period, Configure, Print, Export, Save View, Pin Dashboard, Create Master in Field, Check Books, Repair Books, Audit History, and Related Report.

Text editing takes precedence over global shortcuts. One visible submission creates one in-flight operation. Hidden or disabled UI actions must also be rejected by services.

## Product UX

### Shell and gateway

Use the hierarchy Company/FY → Workspace → current master, voucher, report, document, or configuration.

The shell includes persistent company/FY context, workspace navigation, native toolbar, contextual action strip, breadcrumbs, bottom status bar, command palette, Compact/Comfortable density, and consistent loading, empty, error, locked, read-only, migration, and unavailable states.

The gateway dashboard prioritizes Create Voucher, Resume Draft, Day Book, exceptions, receivables/payables, bank items, stock/reorder issues, favorites, recent objects, books health, and pinned reports/charts.

### Masters

Use hierarchy/filter pane, dense master table, and detail inspector. Every master supports Create, Display, Alter, Disable, Search, Filter, Sort, Create Child, Bulk Create/Alter, Import/Export, Audit History, and Related Reports where permitted.

Bulk changes stage and validate the entire set, then commit atomically. Referenced masters disable instead of disappearing destructively.

Master families are account groups/ledgers/profiles, cost centres/categories, units, stock groups/categories/items, godowns, batches, BOMs, employees, pay heads, salary structures, voucher types/templates/classes, budgets, currencies, exchange rates, and tax/statutory profiles.

Units support exact rational conversions, compound units, multiple alternates, precision rules, cycle rejection, residual handling, migration, restore, and import validation. No quantity path uses floating point.

### Voucher workbench

Use one reusable workbench for headers, party/account context, continuous ledger/item grid, bills, cheques, cost, tax, stock, totals, validation, audit, locks, and contextual actions.

- Return advances or adds a row.
- Command-Return posts/saves.
- Tab/Shift-Tab traverse predictably.
- Escape closes nested detail first and protects unsaved work.
- Validation focuses the exact row and field.
- Alt+C creates a master and restores focus.
- Mode switching preserves compatible data and explains incompatible data.
- Draft recovery never posts automatically.
- Browse, view, alter, reverse, cancel, duplicate, and insert share the workbench.
- Locked vouchers are read-only with an explicit linked correction path.
- Browse-to-correction restores list position, filters, and report context.

Core vouchers are Journal, Payment, Receipt, Contra, Sales, Purchase, Credit Note, and Debit Note. Follow with bill, cheque, cost, GST, stock, order, logistics, manufacturing, post-dated, optional, memo, recurring, template, class, and custom voucher workflows.

Bill-wise accounting includes new/against/advance/on-account references, FIFO and manual allocation, due dates, ageing, interest schedules, settlement workspace, and drill-down.

### Inventory, manufacturing, orders, and banking

Implement stock groups/categories, exact units, godowns/transit, batches/expiry, FIFO and weighted-average valuation, negative-stock policy, backdated recalculation, ageing, reorder, physical stock, stock journals, delivery/receipt/rejection notes, fulfilment, BOMs, manufacturing, by-products, scrap, wastage, overhead, variance, bank imports, matching, unmatching, clearing, bounced cheques, payment advice, MT940, CAMT.053, and explainable fuzzy suggestions.

### Reports, charts, and dashboards

The report catalog covers Financial, Books, Receivables/Payables, GST/Tax, Inventory, Banking, Payroll, Costing, Management, and Exceptions.

Every report provides period/FY, filters, search, saved views, comparison columns, hierarchy, table/chart toggle, row zoom, drill-down, breadcrumbs, context-preserving return, row actions, configurable columns/grouping/sort/density, and print/export from the same definition.

Report families include Trial Balance, P&L, Balance Sheet, Cash Flow, Funds Flow, Ratio Analysis, Group Summary, Day Book, Ledger, Voucher/Sales/Purchase Registers, Cash/Bank Books, Outstanding/Ageing, Interest, GST, Cost Centre/Category, Budget Variance, Orders, Stock, Valuation, Ageing, Reorder, Batches, Godowns, Manufacturing, Payroll, Bank Reconciliation, Audit Exceptions, Books Health, and comparative periods.

Approved no-code datasets are voucher activity, ledger movement, trial balance, P&L, balance sheet, outstanding bills, sales, purchases, GST, stock movement/valuation, banking reconciliation, payroll entries, and audit events.

Charts are Line, Bar, Stacked Bar, Area, Donut, Waterfall, Ageing Distribution, Budget versus Actual, and Cash-flow Bridge. Chart values must reconcile exactly with the table underneath and remain accessible without color alone.

### Documents and exports

Use one document pipeline for tax invoices, vouchers, receipts, payment advice, credit/debit notes, ledger/outstanding statements, orders, delivery/receipt notes, stock transfers, payslips, GST summaries, and financial statements.

Support preview, page settings, branding, headers/footers, page numbers, configurable columns, regional fonts, copies, batch printing, saved profiles, PDF, CSV, XLSX, approved XML, and legacy ASCII/SDF/HTML where required. Totals must reconcile to persisted vouchers or typed reports. Protect spreadsheet exports from formula injection.

## Keyboard compatibility

The action registry owns the following aliases and collision rules:

| Alias | Action |
| --- | --- |
| F4–F9 | Contra, Payment, Receipt, Journal, Sales, Purchase |
| Alt+F8 / Alt+F9 | Sales Order / Purchase Order |
| Ctrl+F8 / Ctrl+F9 | Credit Note / Debit Note |
| Alt+F7 | Stock Journal / Physical Stock |
| Alt+F5 / Alt+F6 | Receipt, Delivery, Rejection, or allocation by context |
| Ctrl+V | Voucher/invoice mode |
| Alt+C | Create master in field |
| Alt+2 | Duplicate voucher |
| Ctrl+R | Narration recall |
| Ctrl+I | Insert while browsing |
| Alt+X | Audit-safe cancel |
| Ctrl+Alt+R | Repair/reindex |
| Ctrl+N | Inline calculator |
| PgUp/PgDn | Previous/next voucher |
| Alt+Z | Report zoom |
| Alt+E | Structured export |
| Alt+N | Comparative columns |
| Alt+S / Ctrl+T | Post-dated voucher |

Native macOS bindings remain supported where they do not conflict with text input or the active workflow.

## Reliability, security, and schema

Preserve backup manifest/version/checksum/byte-count validation, restore staging, atomic replacement, cleanup, company-ID remapping, draft-discard policy, migration interruption safety, local encryption, file-placement and Time Machine checks, WAL cleanup, statement finalization, App Nap activity holds, recovery-key validation, schema-drift tests, company ownership, fiscal-lock triggers, checked money/quantity arithmetic, and performance benchmarks.

No materialized report totals or authoritative in-memory financial cache may be introduced. New persisted features require forward migration, seed compatibility, restore remapping, ownership, audit, naming freeze, schema documentation, and upgrade tests.

## Phased execution

### Phase 0 — v1.1 correctness and release blockers

Objective: prove the currently shipped accounting scope is safe before expanding the product surface.

#### Implementation and automated proof

- ~~Settle audit coverage using forward-only V023/V025 migrations, dedicated mutation actions, one same-transaction audit event, rollback proof, before/after snapshots, and cheque correction taxonomy.~~
- ~~Enforce the inventory-disabled capability boundary across sidebar, menus, palette, help, keyboard routing, dashboard, reports, sheets/deep links, stale company state, and direct services.~~
- ~~Reject and hide `autoPrompt` and `autoSilent`; retain only explicit manual linkage and item-invoice stock workflows.~~
- ~~Complete V14–V22 restore upgrade/remapping, including item-invoice and party-profile rows, dynamic source-company-ID leakage checks, foreign keys, exactly-one restore audit, and explicit draft discard.~~
- ~~Implement central ancestry-aware account eligibility for voucher, invoice, order, banking, payroll, report, batch, and shipped import paths.~~
- ~~Add dual-role party profiles, retained-invalid-selection explanations, regrouping refresh, Alt+C new-account refresh, and UI/service equivalence tests.~~
- ~~Align New/Edit voucher Return, Command-Return, Tab, Shift-Tab, Escape, validation focus, native text precedence, nested sheet capture, and duplicate-submit prevention.~~
- ~~Close local automated P0 proof for accounting balance, numbering, locks, ownership, overflow, GST round-off/PDF, cancellation, bills, cheques, valuation, backdated stock, audit integrity, migration, backup/restore, App Nap holds, and statement cleanup.~~
- ~~Run full tests, rule audit, warnings-as-errors production build, RC bundle/self-test, launch smoke, standard benchmark, and 500k benchmark.~~
- ~~Create the artifact-bound manual acceptance protocol and release-evidence command.~~
- ~~Align v1.1 build metadata through one validated source.~~

#### Remaining release work

- [OPEN — manual] Execute accountant sections A1–A5: company/FY context, account selection, daily voucher keyboard flow, bills, cheques, corrections, audit diffs, reports, GST documents, inventory, valuation, and BOM behavior.
- [OPEN — manual] Execute operator sections B1–B2: cross-machine recovery-key restore, corruption/failure fixtures, migrations, storage policy, App Nap/sleep, and resource soak.
- [OPEN — manual] Execute accessibility/visual/print section C with VoiceOver, visible focus, contrast, themes, resizing, error states, PDF preview, and a physical printer.
- [OPEN — manual] Complete the manual rule review categories explicitly excluded from automation.
- [OPEN — external] Install a valid Developer ID Application identity and approved notarization credentials.
- [OPEN — external] Sign with hardened runtime and reviewed entitlements; notarize, staple, verify with Gatekeeper, retain checksums, and test first install plus prior-version upgrade on a clean supported Mac.
- [OPEN — release ownership] Record release notes, support/incident owner, recovery guidance, retained rollback artifact, and the no-schema-downgrade policy.

Exit evidence: every P0 release-board row references passing automated and named human evidence for the same final checksum; the final downloadable artifact is Developer-ID signed, notarized, stapled, Gatekeeper-accepted, and clean-machine tested.

### Phase 1 — Shared interaction foundation

Objective: establish one interaction and authorization platform so later features do not create isolated screens or duplicated business policy.

1. [PLANNED] Action registry vertical slice:
   - Define stable `AppActionID`, typed context, availability reason, result, and async dispatcher.
   - Migrate Create/Display/Alter/Duplicate/Reverse/Cancel/Print/Export/Drill Down actions for Accounts, Vouchers, Trial Balance, and Day Book first.
   - Drive menu items, toolbar, context strip, command palette, row actions, shortcut help, and deep-link authorization from the same definitions.
   - Prove unavailable actions cannot be invoked through direct routes or services and text editing wins every collision.
2. [PLANNED] Capability and configuration foundation:
   - Introduce `CompanyFeatureSet` for inventory, bill-wise, cost, GST, payroll, banking, orders, batches/godowns, manufacturing, budgets, interest, and later currency support.
   - Introduce versioned `WorkspaceConfiguration` for density, labels, columns, grid behavior, filters, grouping, comparisons, focus behavior, and print/export defaults.
   - Invalidate stale routes, cached actions, sheets, and widgets when company/FY/capabilities change.
3. [PLANNED] Declarative workspace definitions:
   - Add typed workspace, collection, field, and action definitions in compiled Swift.
   - Restrict saved configuration to validated stable identifiers and presentation metadata; never persist financial totals or arbitrary SQL.
4. [PLANNED] Native application shell:
   - Persistent company/FY context, left navigation, native toolbar, contextual action strip, breadcrumbs, and status bar.
   - Compact and Comfortable density with consistent loading, empty, error, read-only, fiscal-lock, disabled-capability, migration, and large-data states.
5. [PLANNED] Shared components in dependency order:
   - Shared account picker backed only by `AccountEligibilityPolicy`.
   - Master workspace first for Groups and Accounts.
   - Voucher workbench shell first for Journal and Payment.
   - Report explorer first for Trial Balance and Day Book.
6. [PLANNED] Proof:
   - Action × workspace × capability × object status × fiscal lock × input-focus matrix.
   - Company-switch invalidation, one-shot dispatch, keyboard collision, VoiceOver, focus restoration, light/dark, resize, and large-collection performance tests.

Persistence: use a forward migration only when saved workspace configuration is ready; include company ownership, migration/restore compatibility, audit policy, naming freeze, and schema documentation in the same slice.

Exit evidence: Accounts, Vouchers, Trial Balance, and Day Book use the shared action/capability/state foundations; no migrated view owns private eligibility or shortcut policy; manual keyboard and VoiceOver acceptance is recorded.

### Phase 2 — Masters parity

Objective: give every business master a predictable Create, Display, Alter, Disable, Search, Bulk, Audit, Import/Export, and Related Report lifecycle.

1. [PLANNED] Ledger foundation: groups, accounts, aliases, and focused party/bank/GST/mailing/interest profiles; complete credit-limit, credit-period, bill-wise, and reconciliation semantics.
2. [PLANNED] Atomic bulk master engine: stage rows, validate uniqueness/ownership/hierarchy/nature/references as one set, show row errors, and commit or roll back the whole batch.
3. [PLANNED] Costing masters: cost categories and cost centres with hierarchy, allocation compatibility, disable rules, and related reports.
4. [PLANNED] Exact quantity platform: unit categories, simple/compound units, multiple alternates, rational conversion graph, precision/display rules, deterministic path selection, cycle rejection, and residual policy—never `Double`.
5. [PLANNED] Inventory masters: stock groups/categories/items, godowns/transit, batches/expiry/manufacture dates, and BOM version lifecycle.
6. [PLANNED] Payroll masters: employees, pay heads, salary structures, effective dates, and statutory applicability.
7. [PLANNED] Transaction/configuration masters: voucher types, templates, reviewable classes, budgets, currencies/exchange-rate profiles, and tax/statutory profiles.
8. [PLANNED] Every family ships with service authorization, audit snapshots, ownership/fiscal-lock policy where applicable, import/export, migration, restore remap, schema drift tests, keyboard flow, VoiceOver, and related-report links.

Exit evidence: every visible master has a complete supported lifecycle; referenced masters disable instead of disappearing; bulk writes are atomic; inline creation uses the same definitions and validation; all new persistence upgrades and restores correctly from every supported schema.

### Phase 3 — Daily accounting workstation

Objective: make the accountant’s complete daily workflow continuous, keyboard-first, explainable, and correction-safe.

1. [PLANNED] Move Journal, Payment, Receipt, Contra, Sales, Purchase, Credit Note, and Debit Note into the shared workbench without changing persisted accounting truth.
2. [PLANNED] Complete bill-wise allocation: new/against/advance/on-account, manual/FIFO allocation, partial settlement, due dates, ageing, interest schedule hooks, and party→bill→voucher drill-down.
3. [PLANNED] Integrate cheque/bank, cost allocation, GST/tax, and stock details into the same transaction and expose the final balanced accounting effect before posting.
4. [PLANNED] Unify browse, display, alter, reverse, cancel, duplicate, insert, and locked-period linked correction while preserving list/report filters, row position, expansion, and breadcrumb context.
5. [PLANNED] Complete draft recovery, model-synchronized undo/redo, narration recall, type/mode transition review, and exact validation focus.
6. [PLANNED] Add post-dated, optional, memo, and recurring lifecycle with explicit status, activation, cancellation, audit, and report treatment.
7. [PLANNED] Expand templates/classes into reviewable drafts with source version, overrides, deterministic ledgers/tax/freight/charges, and no automatic posting.
8. [PLANNED] Implement the context-aware Tally/macOS shortcut matrix through the action registry, including help and collision tests.

Exit evidence: every core voucher is keyboard-complete; one activation produces one durable result; bills/cheques/cost/GST/stock consequences reconcile atomically; locked corrections preserve history; browse-to-correct restores context; accountant acceptance covers all core types.

### Phase 4 — Inventory, manufacturing, orders, banking

Objective: connect physical stock, fulfilment, production, and bank evidence to authoritative accounting transactions.

1. [PLANNED] Exact UOM and valuation: conversion graph, FIFO/weighted-average layers, negative-stock policy, backdated deterministic cascade, progress/cancellation, and authoritative publication.
2. [PLANNED] Location/batch depth: godowns, transit, batches, expiry/manufacture dates, stock ageing, orphan detection, reorder policy, and exceptions.
3. [PLANNED] Orders/logistics: sales/purchase orders, partial fulfilment, pending quantities, over-fulfilment rejection, Delivery/Receipt Notes, Rejection In/Out, invoice conversion, cancellation, and lineage.
4. [PLANNED] Stock operations: Stock Journal, transfers, Physical Stock counts/adjustments, and reconciliation to movement/value layers.
5. [PLANNED] Manufacturing: versioned BOM selection, component consumption, finished output, by-products, scrap/wastage, labour/overhead, variance, reversal, and backdated recalculation.
6. [PLANNED] Banking: bank profiles, fingerprinted/idempotent CSV/MT940/CAMT.053 imports, selected-bank-leg matching, signed direction, match/unmatch/clear/reconcile, explainable fuzzy suggestions, bounce/re-presentation, payment advice, and cheque printing.
7. [PLANNED] Exception workspaces link every reorder, negative-stock, expiry, orphan, manufacturing variance, duplicate import, and ambiguous match to corrective action.

Exit evidence: quantities and values reconcile for every movement; orders reconcile ordered/pending/rejected/fulfilled/invoiced quantities; manufacturing reconciles inputs/outputs/scrap/overhead; bank imports are idempotent and ambiguous suggestions never auto-clear.

### Phase 5 — Reports, charts, dashboards, studios

Objective: turn accounting outputs into navigable, configurable decision workspaces without introducing stored financial truth.

1. [PLANNED] Universal report explorer with typed period/filter state, hierarchy, expand/collapse, search, row zoom/actions, breadcrumbs, and context-preserving return.
2. [PLANNED] Complete Financial, Books, Receivable/Payable, GST, Inventory, Banking, Payroll, Costing, Management, Audit, and Exception catalogs listed above.
3. [PLANNED] Versioned saved views: columns, widths, sorting, grouping, density, filters, comparison periods, drill depth, and table/chart preference.
4. [PLANNED] Approved datasets and stable dimensions/measures backed by typed report services; safe calculated display measures use checked arithmetic only.
5. [PLANNED] Swift Charts with table/chart equality, accessible summaries, non-color encodings, empty/zero/negative/mixed/extreme fixtures, and drill targets.
6. [PLANNED] No-code report/chart studio: choose dataset, dimensions, measures, filters, grouping, comparison, preview, save, pin, print, and export.
7. [PLANNED] Gateway dashboard: actionable exceptions, due receivables/payables, bank/stock work, recent/favorite objects, saved views, and capability-aware pinned widgets.

Exit evidence: every report reconciles to ledger/stock truth and drills to source; saved views survive navigation/migration; chart and table values are identical; large reports meet recorded thresholds; dashboard widgets always lead to actionable context.

### Phase 6 — Documents, PDF, printing, interchange

Objective: render every supported transaction/report through one reconciled document definition and output pipeline.

1. [PLANNED] Define shared document sections, fields, tables, branding, pagination, page settings, and print/export profiles.
2. [PLANNED] Migrate invoices, accounting vouchers, receipts, advice, notes, statements, orders/logistics, stock transfers, payslips, GST summaries, and financial statements.
3. [PLANNED] Native preview, page size/margins/orientation, headers/footers, page numbers, legal identity, logos, columns, regional fonts, copies, and printer profiles.
4. [PLANNED] Batch printing with deterministic selection, identity/count reconciliation, cancellation, failure recovery, and no duplicates/omissions.
5. [PLANNED] PDF, formula-injection-safe CSV/XLSX, approved XML, and required legacy ASCII/SDF/HTML exports from the same report/document totals.
6. [PLANNED] Cheque template designer and explicit, separately confirmed PDF signing with non-destructive failure behavior.

Exit evidence: golden renders/text extraction/pagination/fonts pass; every total equals its authoritative voucher/report; batch counts and identities match; physical printer acceptance is recorded.

### Phase 7 — Offline compliance and payroll

Objective: support statutory preparation and reconciliation while preserving the no-network policy.

1. [PLANNED] GST reconciliation datasets, return preparation, RCM, credit/debit-note and amendment linkage, validation, exceptions, and offline exports.
2. [PLANNED] E-way artifact preparation/import/export lifecycle with provenance; no direct portal submission.
3. [PLANNED] User-imported government-signed IRN/QR retention and printing without generating or implying government signatures.
4. [PLANNED] TDS/TCS applicability, forms, checked calculations, certificates, validated exports, and books reconciliation.
5. [PLANNED] PF, ESI, Professional Tax, Form 16, quarterly exports, effective-rate periods, leap-year/day-count behavior, payslips, and payroll journals.
6. [PLANNED] Every statutory artifact records source period, schema/version, generation/import time, provenance, validation result, and audit event where required.

Exit evidence: statutory outputs reconcile to books and golden fixtures; imported artifacts retain provenance; UI never suggests online filing; payroll acceptance reconciles employee statement, deductions, payable ledgers, and journals.

### Phase 8 — Reliability, migration, import, scale

Objective: make long-lived company data recoverable, diagnosable, importable, and performant under realistic failure and scale.

1. [PLANNED] Multi-window isolation and optimistic locking with stale-write detection, conflict explanation, refresh/retry, and no company-context leakage.
2. [PLANNED] Undo/redo consistency across model, view, focus, validation, totals, autosave, and posted-state boundaries.
3. [PLANNED] Filesystem/WAL/Time Machine/recovery-key diagnostics, storage suitability checks, checkpoint policy, interrupted-write guidance, and versioned recovery formats.
4. [PLANNED] Migration progress, cancellation semantics, failure injection, resumable/non-resumable boundary definition, and valid-old-or-new recovery.
5. [PLANNED] Books Health and Repair: immutable diagnostics, dry run, required backup, explicit confirmation, progress, reindex/repair actions, verification, rollback, and audit.
6. [PLANNED] Tally importer: source inspection, mapping, dry run, exceptions, resumability, fingerprints/idempotency, ownership, checked arithmetic, reconciliation report, and retained provenance.
7. [PLANNED] Standards-compliant CSV/TSV including BOMs, quotes, delimiters, multiline fields, encoding, formula injection, malformed-row reporting, and deterministic retry.
8. [PLANNED] Recorded 10k/100k/500k and documented million-scale gates for posting, reports, restore, import, recalculation, charts, PDFs, memory, statement handles, and cancellation responsiveness.

Exit evidence: windows cannot leak state; migrations/repairs preserve valid old or new state; imports dry-run/resume/idempotently reconcile; performance and cleanup thresholds pass on recorded hardware/datasets.

### Phase 9 — Advanced accounting and company controls

Objective: add advanced management accounting only after daily books, reporting, documents, compliance, and recovery are stable.

1. [PLANNED] Budgets and scenarios by account/group/cost dimension/period with versioning, approval state, variance drill-down, and no mutation of actual books.
2. [PLANNED] Interest profiles, rate periods, grace/day-count/rounding policy, partial settlement, schedule preview, posting approval, reversal, and reconciliation.
3. [PLANNED] Multi-currency masters, exact exchange-rate representation, transaction/base currency, realized/unrealized forex, revaluation, reversal, and comparative reporting.
4. [PLANNED] Deeper costing dimensions, allocation rules, drivers, overhead absorption, profitability, and explainable allocation lineage.
5. [PLANNED] Multi-company comparison with explicit accounting-policy compatibility checks and strict source-company isolation.
6. [PLANNED] Consolidation and elimination entries with ownership, period, currency, policy, reversible lineage, and separate consolidated reporting truth derived from source books plus explicit eliminations.
7. [PLANNED] Offline licensing and device-independent recovery that never blocks access to existing books because a network is unavailable.

Exit evidence: advanced calculations use checked arithmetic and golden schedules; source companies remain isolated; comparisons/consolidation reconcile; eliminations are explicit and reversible; licensing/recovery works without runtime network access.

### Phase 10 — Avelo Extension Language

After no-code definitions stabilize, add a typed parser/AST, validator, capability checker, deterministic evaluator, resource limits, namespaced extension storage, install/enable/disable/update/uninstall, safe mode, audit, backup/restore, and a supported-subset TDL importer. Extensions can define menus, fields, collections, reports, charts, documents, validation, user fields, approved events, service commands, shortcuts, and configuration, but cannot access SQL, network, processes, unrestricted files, or accounting invariants.

## Backlog crosswalk

All existing readiness IDs remain owned by the canonical release board.

- P0 covers GST rounding, numbering, bill allocation, cheque bounce, FY close, locked correction, duplicate prevention, exact quantities, BOM cycles, valuation, overflow, audit evidence, storage, App Nap, migration, state ownership, drafts, backdated stock, keyboard, locale parsing, GST documents, IST, Trial Balance, FY overlap, fiscal locks, corrupt data, registry/company creation, ownership, schema reads, cancellation, inventory boundary, audit coverage, inventory-link policy, restore remapping, and central account eligibility.
- P1 covers statutory tax/payroll, multi-currency, cost dimensions, inventory depth, banking, multi-window, optimistic locking, filesystem/WAL/Time Machine safety, import parsing, undo/redo, Alt+C, Tally importer, ageing, hierarchy integrity, recovery keys, audit depth, guarded workflows, voucher classes, interest, comparisons, Day Book, continuous vouchers, repair, logistics, post-dated lifecycle, batch printing, signing/XML, and shortcut compatibility.
- P2 covers cheque templates, budget variance, orphan batches, payroll edge cases, regional fonts, bank formats, fuzzy matching, consolidation, XLSX fidelity, offline licensing, duplication, narration recall, browse insertion/navigation, calculator, report zoom, email policy replacement, legacy export, expanded shortcuts, gateway, and F11/F12 separation.

No item is complete because a screen or route exists. Completion requires current automated proof and all applicable accountant, operator, keyboard, accessibility, visual, printing, migration, backup, performance, and distribution acceptance.

## Consolidated deferral and checkpoint evidence

The former deferral tracker recorded the following historical contract and verification evidence. These results are evidence from the earlier schema-alignment checkpoint; they do not override the current executable migration list or current-worktree tests.

The initial schema-drift checkpoint identified non-frozen or deferred persistence families including bank statement lines, bill allocations, BOMs/components, budgets, cheques, cost centres/categories, TDS/TCS, expanded inventory item and stock-movement fields, payroll salary/day details, and additional audit actions. Those features remain either explicitly deferred, hidden, or require a future forward migration and naming-freeze update before becoming release-ready.

Historical checkpoint commands and outcomes:

- `swift test --filter SchemaDriftTests` identified the original freeze drift; after alignment, `SchemaDriftTests` and the full suite passed for the frozen contract.
- Inventory and frozen-column tests passed with integer stock quantities and paise-based financial amounts. Non-persisted display DTOs and deferred BOM compatibility models were the only historical `Double` exceptions.
- Financial-write tests passed for inventory capability enforcement, atomic stock-out validation, voucher posting, payroll transaction atomicity, and normalized frozen audit actions.
- Report tests passed for ledger-derived Day Book totals, GST exclusion of opening balances, grouped stock valuation, and cache invalidation after voucher updates.
- SQLite, malformed-UUID, and restore tests passed for strict decoding, integer-safe reads, repository transaction boundaries, frozen-table remapping, and fail-closed deferred workflows.
- App-environment, voucher-view-model, and report-view-model tests passed for cancellable account-tree reloads, stale-safe company closing, typed user-facing errors, and removal of placeholder payroll fields.
- The historical final verification reported 166 executed, 4 skipped, and 0 failures. This must be rerun on the current worktree before being used as release evidence.

No deferred feature becomes active merely because its table, model, route, or service exists. It becomes active only after the master plan phase, schema/naming update, migration, ownership/fiscal-lock/audit coverage, restore mapping, tests, and required manual acceptance are complete.

## Verification and release gates

Test account eligibility across every voucher field, ancestry, role, inactive/foreign account, retained selection, regrouping, creation, ranking, and UI/service equivalence. Test actions across workspace, capability, lock, object state, text editing, menu, toolbar, palette, shortcut, deep link, and service paths.

Test masters for lifecycle, atomic bulk changes, cycles, ownership, profiles, quantities, audit, migration, and restore. Test vouchers for success, rejection, rollback, duplicate submission, bills, cheques, tax, cost, stock, orders, payroll, editing, reversal, cancellation, locks, drafts, mode switching, and lineage.

Test reports/charts for reconciliation, drill-down, comparison, saved views, table/chart equality, checked arithmetic, overflow, and extreme datasets. Test documents for golden PDFs, extraction, totals, pagination, regional fonts, batch identity, print profiles, exports, formula injection, and signing failures.

Test migration, backup, restore, repair, company isolation, ownership, fiscal locks, corruption, statement cleanup, and extension sandbox restrictions.

Manual acceptance must separately cover accountant daily entry, account selection, bills, cheques, GST, inventory, orders, manufacturing, banking, payroll, reports, locked corrections, year close, keyboard-only use, Tally aliases, VoiceOver, focus, themes, resizing, multi-window, PDF/printer output, backup/restore, migration, repair, App Nap, clean installation, upgrades, and extension safe mode.

Avelo is release-ready only when no P0 remains open, full tests and rule audit pass, the release build is warning-free, bundle/signature/self-test/launch smoke pass, performance gates pass, accountant/operator/manual gates pass, conditional features are hidden or honestly labeled, and the final distributable artifact is notarized and clean-machine tested.

## Source consolidation record

Requirements were consolidated from the former V2 execution draft, Tally study guide, deferral tracker, agent task boards, release board, execution checklist, and current repository state. The Tally study guide is archived as research. Obsolete V1/V2 agent boards are not active sources of truth.
