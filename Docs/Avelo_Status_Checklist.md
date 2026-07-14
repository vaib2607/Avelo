# Avelo Status Checklist

Snapshot: 2026-07-15

This is the human-readable progress checklist for Avelo. It complements:

- `Docs/Avelo_Release_Board.md` — canonical issue-level readiness board.
- `Docs/Avelo_Execution_Checklist.md` — remaining `AVL-*` delivery queue.

Checkboxes show evidence, not aspiration: `[x]` means implemented with recorded automated evidence, not necessarily release-accepted; `[ ]` still needs implementation, re-verification, or human acceptance. A feature is not release-ready until current-worktree automated proof and every required accountant, operator, keyboard, accessibility, visual, and distribution gate are complete.

## 1. Foundation and safety — implemented; release acceptance pending

- [x] Native macOS app built with SwiftUI and SwiftPM.
- [x] Strictly offline product: no network APIs, telemetry, or external Swift packages.
- [x] SQLite is the source of truth, with SQLCipher encryption for app-managed company databases.
- [x] Per-company encryption keys are stored in Keychain; recovery keys support cross-machine restore.
- [x] Multi-company registry, create/open/switch/delete flows, backup, restore, and safe staging paths exist.
- [ ] `AVL-P0-036`: make cross-identity restore complete for every supported table. `avelo_voucher_item_lines` is currently missing from company-ID remapping; define explicit remap or discard behavior for scratch voucher drafts.
- [x] Core double-entry accounting uses `Int64` paise, typed errors, checked arithmetic, and deterministic date handling.
- [x] Financial-year creation, lock/unlock, close, reopen, carry-forward, and overlap rejection are implemented.
- [x] Audit records are HMAC-chain protected and company open fails closed on tampering.
- [ ] `AVL-P0-034`: complete same-transaction audit coverage for every shipped mutation, especially FY unlock/reopen, bank statement import/clear/reconciliation, and promoted inventory/BOM/order workflows; chain integrity alone does not prove mutation coverage.
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
- [ ] Harden BOM recipe setup before calling it release-ready: exact quantities, explicit create-versus-update, duplicate-component guards, atomic cycle validation, audit records, and archive/load error handling.
- [x] Bank statement CSV import and baseline reconciliation flow.
- [x] Payroll employees, salary entries, salary vouchers, and payroll register.
- [ ] `AVL-P0-033`: enforce the accounting-only capability boundary: when inventory is disabled, remove Inventory from sidebar, menus, command palette, quick search, keyboard routing, and sheets, and reject direct/deep-link entry consistently.
- [ ] `AVL-P0-035`: complete or hide ledger-voucher `autoPrompt` and `autoSilent`. Prompt mode must collect explicit item/quantity/direction/cost inputs; silent mode cannot ship without deterministic mapping, consent, reversal, valuation, and audit proof. Never infer an item from an account name.
- [ ] `AVL-P0-020`: enforce one voucher keyboard contract—plain Return advances/adds a line, Command-Return posts/saves, Tab/Shift-Tab traverse predictably, and create/edit/help mappings agree.
- [ ] Close the remaining voucher-entry blockers: type-checkable UI composition, single-entry duplicate/recovery, account-creation eligibility plus domain invariants, robust `Alt+C`, and accessible narration recall.
- [ ] Complete the active voucher/BOM worktree and rerun its focused and full regression suites.
- [ ] Confirm the new voucher account-creation, narration-recall, item-mode, and BOM flows manually in the bundled app.

## 4. v1.1 release gate — do next, in this order

1. [ ] Re-run automated proof after the active worktree is settled: relevant targeted tests through `./Scripts/swiftw.sh test --filter ...`, `make test`, `make rc-local`, same-machine benchmark checks, and `make launch-smoke`. Record the commit/worktree identity and all skipped tests. The current launch-smoke target validates/self-tests the bundle; separately launch the GUI with `open dist/Avelo.app` in a normal session.
2. [ ] Run accountant acceptance for invoice rounding, bill settlement, cheque bounce/re-presentation, BOM handling, valuation, backdated stock corrections, trial balance, cancellation, and year close/reopen.
3. [ ] Run operator acceptance for company create/restore, corrupt database recovery, iCloud-exclusion policy, migrations, App Nap/sleep behavior, and statement-resource cleanup.
4. [ ] Run keyboard-entry acceptance for Tab, Shift-Tab, Return, validation failures, line insertion, and Tally shortcut routing.
5. [ ] Run accessibility acceptance for VoiceOver names/values/grouping, visible focus, keyboard-only completion, contrast, non-color-only status, resizing, empty states, and error recovery on shipped paths.
6. [ ] Run visual/document acceptance for B2B invoice PDF layout, GST breakdown, printing totals, light/dark appearance, resizing, and company switching.
7. [ ] Select and document the public distribution path. The current bundle is ad-hoc signed and therefore only a local RC; public release requires Developer ID signing plus notarization (or a separately approved Mac App Store path), hardened-runtime/entitlement review, and a clean-Mac install/launch test.
8. [ ] Align bundle metadata with v1.1. `Scripts/bundle.sh` currently emits `CFBundleShortVersionString=1.0` and `CFBundleVersion=2`; release version/build identity must come from one declared source and match the changelog/tag/artifact.
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
