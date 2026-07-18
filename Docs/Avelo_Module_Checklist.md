# Avelo Module Checklist

Snapshot: 2026-07-19

This is the layer/capability review map and per-slice acceptance checklist. The live filesystem is the authority for file inventory; this document deliberately does not copy every Swift filename because a handwritten manifest becomes stale as files are added, renamed, split, or removed.

Out of scope: cloud sync, remote login, remote protection, and other network-dependent features prohibited by Avelo's offline rule.

Legend: `[ ]` pending · `[x]` evidence recorded · `[-]` deferred with reason · `[!]` blocked with dependency

## Maintenance contract

- Review changed files through their owning layer and product slice below; a checked directory never implies every future file in it is automatically accepted.
- New directories under `Avelo/` or new top-level feature families require an explicit owner row here and architecture review.
- New migrations require schema, naming-freeze, restore, compatibility, and schema-drift proof in the same slice.
- New files are discovered by `make docs-check`; no manual filename inventory update is required.
- Checkboxes record review evidence for an identified worktree. Source changes invalidate only the affected layer/slice, not unrelated historical checks.
- Readiness state and execution order remain in the release board and execution checklist; this file does not create parallel backlog IDs.

## Layer ownership map

| Layer | Live path | Review focus | Current state |
| --- | --- | --- | --- |
| Composition and routing | `Avelo/App/` | lifecycle, environment construction, company/FY context, routing, capability invalidation | [ ] Re-review affected files on active worktree |
| Actions and keyboard | `Avelo/Core/Actions/`, `Avelo/Core/Keyboard/` | one-shot dispatch, context, text precedence, shortcut collisions | [ ] Manual keyboard proof remains |
| Models | `Avelo/Core/Models/` | plain value semantics, checked money/quantity, strict decoding, ownership identifiers | [ ] Re-review V027–V029 models |
| Database and migrations | `Avelo/Core/Database/` | forward migration, triggers, restore, encryption, valid-old-or-new failure behavior | [ ] V027–V029 proof remains under `AVL-P1-045` |
| Repositories | `Avelo/Core/Repositories/` | SQL only, strict mapping, ownership/FY scope, no invented business rules | [ ] Re-review canonical-track queries |
| Services | `Avelo/Core/Services/` | business rules, atomic writes/audits, typed errors, locks, rollback | [ ] Re-review affected posting/report/inventory services |
| Validation and utilities | `Avelo/Core/Validation/`, `Avelo/Core/Utilities/` | reusable policy, checked arithmetic, no silent fallback | [ ] Re-review affected validation paths |
| Shared UI | `Avelo/Shared/` | reusable components, native behavior, focus, accessibility, themes | [ ] Input and money-field manual proof remains |
| Feature UI | `Avelo/Features/` | ViewModel/service boundary, keyboard flow, errors, loading/empty states, VoiceOver | [ ] Reports and vouchers changed in active worktree |
| Resources | `Avelo/Resources/` | schema/seed equivalence, deterministic bundled data | [x] No active resource change detected |
| Tests | `Tests/AveloTests/` | observable behavior, regression, real SQLite fixtures, failure/rollback paths | [ ] Final full-suite and RC proof remains |
| Build/release | `Package.swift`, `Makefile`, `Scripts/`, `ReleaseVersion.env` | offline dependencies, reproducible commands, bundle/signing/artifact identity | [ ] Public-distribution acceptance remains |
| Product/release docs | `Docs/` | owner consistency, evidence identity, no aspirational completion | [ ] Synchronize active V027–V029 slice |

## Capability review map

| Capability | Primary layers | Required proof before acceptance |
| --- | --- | --- |
| Company/FY lifecycle | App, Database, Repositories, Services, Onboarding/Settings | ownership, overlap/lock, migration, backup/restore, operator acceptance |
| Accounts and masters | Models, Repositories, Services, Accounts | hierarchy, eligibility, audit, inline creation, keyboard/VoiceOver |
| Vouchers and drafts | Models, Repositories, Services, Vouchers | balance, numbering, locks, audit, recovery, duplicate submission, accountant keyboard flow |
| Reports | Repositories, Services, Reports | live reconciliation, period scope, malformed-data failure, drill/return, accountant acceptance |
| Inventory/manufacturing/orders | Models, Repositories, Services, Inventory | quantity/value reconciliation, ownership/locks, reversal, restore, accountant acceptance |
| GST/compliance/payroll | Models, Services, GST/Payroll, documents/exports | checked calculations, statutory fixtures, provenance, offline policy, accountant acceptance |
| Banking | Repositories, Services, Banking | selected-bank-leg semantics, idempotency, audit, signed direction, accountant acceptance |
| Audit/security/recovery | Database, Repositories, Services, Audit | chain integrity, encryption, corruption failure, restore, operator acceptance |
| Shell/actions/configuration | App, Actions, Keyboard, Shared, Onboarding | capability invalidation, context, shortcut collisions, focus, accessibility |
| Bundle/distribution | Build scripts and docs | warnings-as-errors, RC gates, GUI smoke, signing/notarization, clean-machine install/upgrade |

---

## Per-slice acceptance criteria

### Slice 1 — Foundation
- [x] App launches and shows the company picker.
- "New Company" wizard collects name, address, GSTIN/PAN, base currency, and a financial year (start, end, books-begin date) and a default chart of accounts choice.
- On confirm, a `.sqlite` file is created at `Application Support/Avelo/Companies/<uuid>.sqlite` and seeded with the full schema + default voucher types + default groups + default ledgers.
- The registry DB records the company.
- The dashboard shell renders with the company name, active FY, and a "no data yet" empty state.
- [x] "Open Backup" works.
- [x] Switching the FY in the toolbar updates the active FY.
- [x] Company Info menu exposes local company actions: select company, create company, backup, restore, and close company.
- [x] New Company wizard captures every field-level input required by the spec.

### Slice 2 — Accounts
- Accounts screen lists groups and ledgers in a tree.
- Add ledger under a group; opening balance and side captured.
- Edit ledger; edits to opening balance are allowed only on the first FY.
- Disable ledger; disabled ledgers do not appear in pickers but still appear in historical reports.
- Add group; reorder via sort_order.
- [x] F11 company-features panel exposes local accounting and inventory toggles in one place.
- [x] F12 configuration exposes local app settings in one place, including data paths and voucher-entry behavior.
- [x] Bill-wise Adjustments support `New Ref`, `Agst Ref`, `Advance`, and `On Account`.
- [x] Batch-wise tracking captures manufacture date and expiry date.
- [x] Zero-valued entries support free samples and gifts without breaking inventory posting.

### Slice 3 — Vouchers
- [x] Voucher list with filters: FY, type, date range, party, narration contains.
- [x] Voucher entry with all 10 types, live debit/credit/diff footer, Tab/Enter shortcuts, party picker, narration.
- [x] Save posts the voucher inside a single DB transaction; audit event is written.
- [x] Edit a posted voucher in an open FY.
- [x] Reverse a posted voucher; the reversal voucher has opposite lines and a `reversal_of_id` link.
- [x] Locked FY rejects any write at the trigger level.
- [x] Accounting voucher variants explicitly cover contra, payment, receipt, journal, sales, purchase, debit note, and credit note entry flows.
- [x] Inventory vouchers explicitly cover purchase order, sales order, receipt note, delivery note, rejection in, rejection out, stock journal, and physical stock.

### Slice 4 — Reports
- [x] Ledger report: account + period; running balance in paise.
- [x] Trial balance: all accounts, debit total, credit total, diff column.
- [x] P&L: income minus expense, broken into sections.
- [x] Balance sheet: assets vs liabilities + equity, group hierarchy respected.
- [x] GST summary: month picker, input vs output, CGST/SGST/IGST/cess, net payable.
- [x] Day book: chronological voucher list.
- [x] Drill-down: any row in any report jumps to the source voucher (open in read-only editor).

### Slice 5 — Inventory
- [x] Toggle inventory on/off in Settings.
- CRUD on stock items; choose valuation method.
- [x] Record stock in (purchase, opening) and stock out (sale, issue) with explicit qty and unit cost.
- After saving a `sales` or `purchase` voucher, prompt to record stock movement; user confirms and posts.
- [x] Stock valuation report (FIFO or WA per item) is available.
- [x] Stock master coverage includes stock groups, stock categories, units of measure, and godowns.
- [x] Bill of Materials supports assembled stock items with component breakdowns.
- [x] Physical Stock vouchers support manual inventory counting and reconciliation.
- [x] Stock Journal vouchers support inter-godown transfers and stock adjustments.

### Slice 6 — Banking, backup, audit
- [x] Bank account identified by `is_bank_account = 1`.
- [x] Reconciliation view shows uncleared bank book entries and accepts statement date + amount matches.
- [x] Mark cleared; clears with timestamp.
- [x] Backup export to chosen `.avelobackup` (zip of the SQLite file + sidecar manifest).
- [x] Restore from `.avelobackup` creates a new company in the picker.
- [x] Audit log view: filters by entity, action, date range; shows before/after JSON for each event.

### Slice 7 — Payroll
- [x] Employee CRUD; termination via end date.
- [x] Salary voucher: pick employee + month; pre-fills gross from base salary; user enters deductions; net is auto-computed; saves as a single voucher with Salary Expense Dr / Cash or Bank Cr.
- [x] Salary register per month per employee.

### Slice 8 — Hardening
- [x] Voucher templates: save current draft as a template, load template into a new draft.
- [x] Last-used-account sort in account picker.
- [x] Multi-line paste (TSV) parses into lines.
- [x] Dark mode respected.
- [x] Full keyboard shortcut help dialog.
- [x] App icon set (placeholder; user replaces later).
- [x] Keyboard shortcuts cover F1 through F12 and the app-level navigation shortcuts listed in the spec.
- [x] Full field-level master coverage is reconciled against the spec for company, group, ledger, stock item, voucher, financial-year, inventory, and GST screens.
