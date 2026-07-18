# Avelo Master PRD

This is the normative source for user-visible Avelo behavior. It defines required outcomes and failure behavior; it does not claim that each outcome is implemented or release-accepted.

Authority order:

1. `Avelo_Rules.md` owns non-negotiable invariants.
2. This PRD owns product behavior and scope.
3. `Avelo_Architecture.md` owns dependency and transaction boundaries.
4. `Avelo_Schema.md`, executable migrations, and `SchemaVersion.current` own persistence.
5. `Avelo_Release_Board.md` owns the canonical readiness verdict. `Avelo_Status_Checklist.md` summarizes state; `Avelo_Execution_Checklist.md` owns next work and evidence.

Current verdict: **NOT READY FOR PUBLIC PRODUCTION**.

The complete product roadmap, Tally-parity scope, phased delivery order, and cross-document ownership are defined in `Avelo_Master_Product_Execution_Plan.md`.

## 1. Product definition

Avelo is a fully offline native macOS accounting application for Indian small businesses. It uses SwiftUI, Swift Package Manager, and one local SQLite/SQLCipher database per company. It is keyboard-first, single-user, and designed around double-entry bookkeeping, auditability, recovery, Indian financial years, GST-aware invoicing, and local ownership of data.

The product uses a modern native shell with Tally-inspired contextual actions, continuous voucher entry, inline master creation, hierarchical report drill-down, configurable workspaces, no-code reports/charts/documents, and native macOS accessibility. Company capabilities and per-screen behavior are separate. Direct government API calls, direct email dispatch, and arbitrary extension execution are outside the offline product contract.

The user explicitly supplies or selects every business input and posting intent. Avelo may deterministically derive reviewable GST, CESS, valuation, COGS, round-off, totals, and reports from those inputs and stored masters. It never infers a party/item/price from history and never posts a voucher because of a background event.

### Goals

- Fast daily voucher entry with predictable keyboard flow.
- Exact paise and quantity arithmetic with fail-closed accounting controls.
- Multi-company local books, backup, recovery-key restore, and forward migrations.
- Reconciled financial, GST, outstanding, banking, payroll, and inventory views for the supported scope.
- Native macOS accessibility, focus behavior, appearance, and distribution quality.

### Non-goals under the offline rule

- Cloud sync or hosted backup.
- Multi-user roles or remote collaboration.
- Direct GST portal, IRN, government-signed QR, e-way-bill, email, telemetry, licensing, or update APIs.
- Mobile/web companion clients.

Offline import or export files may be supported when the format, validation, privacy, and reconciliation contract is explicitly approved.

## 2. Users

- **Owner/operator:** creates companies, manages FYs, backup/recovery, settings, and business controls.
- **Accountant:** performs daily keyboard entry, correction, reconciliation, reporting, GST, inventory, and payroll workflows.
- **Auditor:** inspects immutable audit history, source vouchers, report filters, and reconciliation evidence.

Avelo assumes one local user at a time. Multi-window/concurrent-editor behavior is not production scope until conflict and company-context isolation are designed and accepted.

## 3. Terms

| Term | Meaning |
|---|---|
| Paise | The atomic money unit; ₹1.00 = 100 paise. |
| Exact quantity | Rational/fixed-point quantity represented without `Double`. |
| Group | A hierarchy node used to classify and aggregate accounts. |
| Ledger/account | A postable leaf account. |
| Voucher | Header plus two or more balanced ledger lines and optional workflow/item rows. |
| Reversal | A linked corrective voucher/movement with opposite effects; the original remains. |
| Cancellation | A preserved voucher and number with status, reason, actor, time, audit, and optional linked corrective voucher. |
| FY | Indian financial year, normally 1 April through 31 March. |
| FY lock | A freeze on covered financial writes; separate from FY close. |
| FY close | Publication of exact next-FY opening snapshots; reversible through explicit reopen. |
| Ledger mode | Voucher entry using explicit debit/credit or supported single-entry presentation. |
| Item-invoice mode | Explicit Sales/Purchase entry using item, quantity, rate, party, and ledger inputs with atomic tax/stock/accounting effects. |
| Release evidence | Proof tied to one worktree, machine/toolchain, command, and built artifact. |

## 4. Product and persistence model

- One registry database discovers many companies; it stores no financial data.
- One company owns many FYs, groups, ledgers, voucher types, vouchers, items, employees, banking rows, and audit events.
- One voucher owns two or more accounting-track rows and may own bill allocations, cheque state, item-invoice lines, cancellation/reversal lineage, and inventory-track effects.
- One FY close owns carried opening rows for the next FY; it does not rewrite historical ledger-master openings.
- One inventory item owns exact unit metadata and stock/valuation history; a finished item may own a BOM recipe.
- Audit events are immutable, ordered, HMAC-linked evidence for a specific company.

The readable schema is `Avelo_Schema.md`; current executable schema is v27.

## 5. Default company seed

`Avelo/Resources/Seed/DefaultChartOfAccounts.json` is authoritative. The v1.1 seed contains:

- 28 groups, including 16 top-level groups;
- 35 ledgers, including cash, banks, debtor/creditor controls, GST/CESS, round-off, sales, purchase, payroll, stock, capital, loan, income, and expense ledgers; and
- 10 system voucher types.

Seed codes used by posting/reporting are compatibility identifiers. A seed change needs migration/backfill policy, code-presence and count tests, restore coverage, and documentation updates.

| Code | Display | Abbreviation | Default prefix |
|---|---|---|---|
| journal | Journal | JV | JV |
| sales | Sales | SALES | S |
| purchase | Purchase | PURCH | P |
| payment | Payment | PAY | PAY |
| receipt | Receipt | RCT | RCT |
| contra | Contra | CON | CON |
| creditNote | Credit Note | CN | CN |
| debitNote | Debit Note | DN | DN |
| opening | Opening Balance | OPN | OPN |
| payroll | Payroll | PAYROLL | PAYROLL |

Numbers are allocated inside the posting transaction per company/FY/type and formatted as `<prefix>/<short-FY>/<padded sequence>`. A failed transaction does not consume a number; a cancelled number is never reused.

## 6. Company lifecycle

### Company picker

- Lists registry entries without opening all company files.
- Offers New Company, Open Company, Restore Backup, and an explicitly labelled Demo Company.
- Missing/moved files produce recovery or restore guidance; Avelo never creates a blank replacement silently.
- Opening verifies key/schema, runs supported migrations with progress, verifies audit integrity, selects an active FY, and publishes one `CompanyContext`.

### New company

One reviewable sheet collects legal/contact/GST fields, the initial FY, the default chart, and inventory choice.

- Company name is required and unique; PAN/GSTIN are optional but validated when supplied.
- INR is the current base currency.
- Initial FY defaults from the Indian accounting calendar; books-begin may be later within it.
- Inventory defaults off. Manual and auto-prompt values are stored for compatibility; unsupported production behavior remains blocked by `AVL-P0-035`.
- File, Keychain key, migrations, seed, and registry publication use commit/compensation semantics.
- After success, Avelo shows the recovery key and prevents closing until the user acknowledges saving it. The key is not included in backups.

### Switch, close, and delete

- Switching replaces the whole company/FY/database context, cancels stale work, invalidates derived caches, and resets unsafe navigation.
- Closing releases the handle and context without deleting data.
- Delete is an explicit destructive company-file operation with clear consequences and rollback limits; it is not the voucher/account deletion model.

## 7. Financial years and opening balances

- FYs for a company cannot overlap. A date resolves to exactly one FY or fails closed.
- Lock/unlock and close/reopen are separate, confirmed, audited operations.
- A lock freezes every covered dated mutation at service and trigger boundaries.
- Close publishes one exact opening snapshot per ledger into the next FY, exactly once.
- Reopen removes the published snapshot; re-close regenerates it deterministically.
- Ledger-master opening balances describe the initial books. Carried FY openings live in `avelo_financial_year_opening_balances`.
- Reports identify and reconcile their opening source.

## 8. Accounts workspace

- Shows the hierarchical group tree and postable ledgers with search, current balance, and master details.
- Group create/update rejects direct or indirect cycles, cross-company parents, and nature-incompatible hierarchy.
- Ledger create/update validates company, group, code/name, opening amount/side, bank flag, GST/mailing fields, bill-wise policy, and fiscal lock.
- Referenced ledgers are disabled, not hard-deleted.
- Creating an account from voucher entry returns to the originating field, preserves the draft, and revalidates eligibility.
- Account eligibility resolves the complete group ancestry using stable semantic codes and explicit profiles; account/group display names never determine accounting meaning. The same decision governs pickers, voucher validation, item invoices, orders, banking, payroll, reports, imports, edits, duplication, and restore checks. Invalid retained selections remain visible with a reason until replaced.

## 9. Voucher workspace

The list filters by FY/date/type/party/status and opens source detail without losing filter/position context. Locked vouchers are read-only and expose only allowed correction actions.

### Common editor behavior

- Header: type, date, party/against, narration, workflow fields, and read-only number.
- Posting remains actionable while invalid so activation can display the first typed error; only an in-flight attempt disables it.
- A one-shot gate prevents rapid repeated activation from creating duplicates.
- Draft autosave is scratch data. Resume always revalidates; a draft never posts itself.
- Success clears the saved draft, invalidates affected derived state, and identifies the durable voucher.

### Ledger mode

- Continuous debit/credit rows with searchable ledgers and live debit, credit, and difference totals.
- At least two positive lines are required and debit equals credit.
- Accounts must be active, postable, same-company ledgers.
- Contra, Payment, and Receipt may present a single-entry workflow while persisting an ordinary balanced voucher.
- Bill and cheque inputs persist atomically with the voucher when applicable.

### Item-invoice mode

- Available only for explicit Sales/Purchase item entry with inventory enabled.
- The user selects party, sales/purchase ledger, item, exact quantity, and rate.
- Item master taxability/rates plus place of supply deterministically derive taxable value, CGST/SGST/IGST/CESS, round-off, ledger lines, item lines, and stock/valuation effects.
- Voucher, number, ledger lines, `avelo_voucher_item_lines`, bill workflow, stock effects, and audit commit or roll back together.
- Edit, reverse, cancel, restore, reporting, and PDF retain item/tax lineage.

### Ledger-voucher inventory linkage

- `manual`: no stock effect; the user records stock separately.
- `autoPrompt`: may ship only when the prompt collects explicit item, exact quantity, direction, date, and cost/valuation inputs and handles edit/reversal/cancellation/restore/audit.
- `autoSilent`: unavailable until deterministic mapping, consent, reversal, valuation, audit, and accountant acceptance close `AVL-P0-035`.
- Account-name or history-based item inference is forbidden.
- Item-invoice mode never needs a follow-up link prompt because its effects are atomic.

### Edit, reverse, and cancel

- Open-FY edits use one audited transaction with complete before/after evidence and dependent-row reconciliation.
- Locked-FY records are not edited in place.
- Reversal creates linked opposite financial effects. Cancellation preserves record/number/reason/actor/time/audit and defined report treatment.
- Any dependent bill, cheque, item, stock, valuation, report, or audit update succeeds atomically or the correction fails.

## 10. Dashboard and reports

The dashboard shows company/FY context, voucher quick entry, account-tree totals, recent vouchers, monthly P&L, and responsive KPIs for cash, bank, receivables, payables, month sales/purchases, GST payable, and stock value when enabled.

The reports workspace includes supported ledger, trial balance, P&L, balance sheet, GST, day book/activity, cash/bank, outstanding/ageing, stock valuation/register/ageing, and related drill-downs.

Every visible report:

- exposes its complete filter state and empty/error state;
- derives authoritative totals from stored entries through SQL;
- uses checked arithmetic and strict decoding;
- states reversed/cancelled/opening treatment;
- reconciles to the ledger or stock source appropriate to it;
- preserves context on drill-down and return; and
- validates export/print output against the same persisted totals.

Do not hard-code a report tile count in product copy.

## 11. Inventory, orders, and BOM

When inventory is disabled, every entry point and mutation service rejects or hides inventory (`AVL-P0-033`). When enabled:

- item masters store unit, optional exact alternate-unit conversion, valuation policy, GST/HSN metadata, and active state;
- stock movements are immutable/reversible and fiscal-lock/company aware;
- FIFO and weighted-average valuation use exact layers and deterministic residual paise;
- backdated correction recalculates every affected downstream layer/COGS before atomic publication;
- Sales/Purchase orders have persisted header/line/status basics; fulfilment, rejection, logistics, and manufacturing remain deferred until their board items close;
- BOM recipes use exact output/component quantities, reject duplicate/circular components, and are recipe setup only until production vouchers ship.

## 12. Payroll, banking, GST, and audit

### Payroll

- A shipped Payroll module remains discoverable with an empty state and New Employee action.
- Employee create/update/termination, salary inputs, payroll entry, balanced salary voucher, and audit commit consistently.
- Statutory PF/ESI/PT/TDS/form exports are deferred unless the release board says otherwise.

### Banking

- Bank statement import is local-file only and preserves unmatched rows.
- Match/unmatch/clear behavior names the selected bank ledger leg, signed direction, idempotency/fingerprint policy, and audit effect.
- Cheque issue, bounce reversal, and re-presentation preserve lineage and numbering.

### GST and documents

- B2B GST invoice/PDF supports the approved field matrix, HSN/SAC, place of supply, tax split, CESS, round-off, and item detail.
- Offline CSV/document exports reconcile to the same voucher/report data and protect against formula/encoding hazards.
- Avelo does not claim to issue IRNs or government-signed QR codes under R-1.

### Audit

- Every shipped meaningful mutation writes exactly one same-transaction event with its required before/after/reason policy.
- The chain is immutable and HMAC-linked, but chain integrity does not prove action coverage; missing action families remain `AVL-P0-034`.
- Audit view filters events and displays readable before/after evidence without mutating it.

## 13. Backup, restore, and recovery

### Backup

- Exports a consistent encrypted database through staging and atomic destination replacement.
- Writes a versioned manifest with schema, company, original filename, timestamp, byte count, and SHA-256.
- Failure preserves the prior destination and source company.

### Restore

- Validates manifest support, identity, byte count, and checksum before mutation.
- Opens with a local key or validated recovery key; rejects wrong/typo/corrupt keys before publication.
- Stages and migrates supported versions, assigns collision-safe company identity/name/file, remaps every company-scoped table, recreates required triggers, and checks integrity/FKs/ownership/FY overlap/audit.
- Never overwrites an existing company and compensates file/Keychain/registry on failure.
- Cross-identity item-invoice restore is blocked by `AVL-P0-036` until `avelo_voucher_item_lines` remapping and scratch-draft policy are implemented and proved.

## 14. Shell and settings

- Sidebar destinations: Dashboard, Vouchers, Accounts, Reports, Inventory, GST, Payroll, Banking, Audit, Settings.
- Company/FY/module context is always visible.
- Settings manages company details, inventory capability/link policy, FY create/lock/close flows, backup/restore, and version/schema/support information.
- Optional modules use one capability decision across sidebar, menus, command palette, quick search, keyboard, sheets/deep links, dashboard, and services.

## 15. Keyboard contract

The following is normative. Differences among editors, `KeyboardShortcutMap`, global monitor, menus, or help are blockers under `AVL-P0-020`/`AVL-P1-044`.

| Action | Canonical shortcut |
|---|---|
| Voucher row advance/add | Return in the amount flow |
| Post/save voucher | Command-Return |
| General form save | Command-S where applicable |
| Cancel/back | Escape; Command-period where advertised |
| Traverse | Tab / Shift-Tab |
| Command palette | Command-K |
| Quick search | Command-/ |
| Dashboard through Settings | Command-1 through Command-0 |
| New Company | Command-Shift-N |
| Open Company | Command-Shift-O |
| Backup | Command-Shift-B |
| Restore Backup | Command-Shift-R |
| Voucher families | F4-F9; Control-F8/F9 for credit/debit notes |

Context-specific bindings beat global bindings. Text input wins unless its editor explicitly owns the chord. Shortcut help shows every active binding and collision rule. Destructive confirmation never inherits the post shortcut accidentally.

## 16. Cross-cutting UX

### Formats

- Money storage: signed `Int64` paise; display uses Indian grouping and explicit sign.
- Quantity storage: exact integer/rational fields; no authoritative `Double`.
- Date storage: `yyyy-MM-dd`; timestamps: documented UTC ISO format; display: Indian English date conventions.
- User parsing is locale-aware but stored values are unambiguous.

### Errors and feedback

- Invalid input identifies the field/problem and a recovery action without discarding the draft.
- Business errors use the shared actionable error host; informational/success banners remain until dismissed or replaced.
- Loading, empty, success, validation, destructive-confirmation, corruption, and recovery states exist for every shipped workflow.
- Corrupt persisted values never become valid-looking defaults.

### Accessibility and layout

- Every control has a stable accessible name, value, role, grouping, and error relationship.
- Icon-only actions have help and VoiceOver labels; focus is visible; status is not color-only.
- Every shipped workflow completes keyboard-only and with VoiceOver.
- Primary actions remain reachable at 1080×720 and larger sizes; dense tables scroll within their own region.
- Light/dark appearance, increased contrast, reduced motion, resizing, focus, and error recovery are release gates.

## 17. Deferred scope

- Multi-user roles, remote collaboration, consolidation, and multi-currency.
- Godowns/transit, batches/expiry, negative-stock policy, by-products/scrap, and manufacturing execution beyond BOM recipe setup.
- Advanced order fulfilment/rejection/logistics.
- Cost-centre/category allocation, budgets, voucher classes, interest policies, and comparative reports until their board items close.
- Full GST return/import/reconciliation breadth, TDS/TCS, statutory payroll exports, regional-script PDF matrix, print profiles, DSC, legacy exchange formats, and Tally import.
- Automatic recurring posting; templates may create reviewable drafts only.

A deferred capability is absent from production entry points or clearly unavailable with a typed error. A placeholder route/model does not make it shipped.

## 18. Release acceptance

For each shipped workflow, acceptance includes:

- deterministic success and failure behavior;
- service/repository/migration/restore/company-isolation/audit regression proof as applicable;
- accountant verification of accounting, tax, valuation, and document outcomes;
- operator verification of create/open/switch/backup/restore/recovery/migration behavior;
- keyboard, VoiceOver, focus, contrast, resize, appearance, visual/PDF/print checks; and
- evidence tied to the same commit/worktree and artifact.

The release also requires warnings-as-errors, full tests, rule audit, RC bundle validation/self-test, benchmarks, separate GUI launch, aligned v1.1 metadata, approved Developer ID/notarization or Mac App Store distribution, clean-Mac install/launch/upgrade proof, artifact checksum/retention, rollback policy, support/incident ownership, and every P0 closed on `Avelo_Release_Board.md`.
