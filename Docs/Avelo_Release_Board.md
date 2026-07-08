# AVELO Release Board

This is the repo-tracked `P0/P1/P2` execution board for the release push. Each open issue appears once, carries one severity, and maps back to the master execution checklist.

Current release target:
- `v1.1` is the performance, accuracy, and reliability hardening release.
- The current benchmark focus is on repeatable local measurement for cold launch, core voucher/report paths, backup/restore, soak, stress, and million-voucher runs on the same machine and dataset.

Severity rules:
- `P0`: release-blocking correctness, data integrity, fiscal lock, restore, or core offline-behavior risk
- `P1`: high-priority shipped-path gap that can cause broken workflow, bad UX trust, or incomplete validation
- `P2`: lower-priority release work, deferrable module decisions, or hardening/polish items that do not block core correctness by themselves

Module ship status:
- `Exposed, not Ready`: company setup, company switching, FYs, accounts, vouchers, reports, inventory, payroll, banking, audit, backup/restore, and the offline shell remain available for development and accountant QA, but the open P0 catalogue below blocks a Ready designation.
- `Conditional`: inventory valuation, payroll compliance, banking reconciliation, GST filing, and legal-document output must be labelled incomplete anywhere they remain visible.
- `Deferred`: features whose broader workflows are still explicit stubs, including BOM costing/production, TDS/TCS, cost-centre/category, and advanced order/logistics flows, cannot be counted as shipped merely because models, fields, routes, or placeholder screens exist. Core cheque bounce/re-presentation and BOM cycle-safe persistence now ship-path test, but broader adjacent workflows remain open until the canonical backlog closes them.

Release split rule:
- If it affects correctness, data loss, or the app's ability to open and save reliably on day one, it belongs in `V1`.
- If it improves offline merge, security, scale, or benchmark tooling but does not block launch, it belongs in `V2`.
- If it is mainly enterprise hardening, resilience polish, or rare-edge-case protection, it belongs in `V3`.

## Release Split

### V1: Must Ship
- Fail loudly on malformed UUIDs instead of substituting fresh IDs. Status: done in shipped repository, registry, and report-decode paths with regression coverage.
- Keep restore safe and deterministic; minimize mutation during restore and preserve checksum verification.
- Preserve currently tested WAL, foreign-key, transaction, and audit-immutability primitives while closing the open fiscal-lock, strict-decoding, tamper-evidence, and company-isolation requirements in the canonical P0 catalogue.
- `VoucherService.postBatch` commits in bounded chunks of 500 drafts; if a later chunk fails, already-committed chunks remain durable and the failing/later chunks are not partially persisted.
- Add basic handling for missing or moved company files that gives a clear recovery path or explicit re-link workflow. Status: core open and backup paths now honor registry `sqlite_file_name`, preserve a legacy `id.sqlite` fallback, and fail with explicit re-link or restore guidance when the registered file is missing.
- Add minimum viability checks for permissions, disk-full, and backup-write failures so the app fails cleanly.
- Prevent obvious large-ledger or report slow paths that would make core accounting unusable at launch.

### V2: Should Ship After Launch
- Migrate from plain UUIDs to UUIDv7 for time-sortable IDs and better offline merge behavior.
- Add stronger restore hardening and more explicit integrity verification around imported backups.
- Add basic large-dataset performance work: better pagination, query-plan tuning, prepared-statement reuse, and benchmark-driven regression checks.
- SQLCipher at-rest encryption is active for app-managed company databases with per-company raw keys stored in Keychain and user-custody recovery keys for cross-machine restore.
- Backup manifests carry `manifestVersion`; restore rejects unsupported versions before opening imported bytes and verifies checksum/byte-count before encrypted open or copy.
- Backup export stages the database and manifest through same-directory temp files before atomic replacement; restore/migration paths continue to stage work before final replacement.
- Add clearer recovery for unusual filesystem cases like network volumes or antivirus locks.

### V2 Encryption Performance Pass — 2026-06-20
- Encrypted `postBatch` 10k vouchers: 5.226s vs 7.858s baseline, below the 9.037s +15% threshold.
- Encrypted `postBatch` 100k vouchers: 97.805s vs 92.505s baseline, below the 106.381s +15% threshold; no SQLCipher KDF/page-size tuning applied.
- `PRAGMA journal_mode` remains `wal` for encrypted on-disk benchmark fixtures.
- Encrypted `postBatch` failure semantics remain chunked at 500 drafts: completed chunks persist, failing chunk rolls back, later chunks are not attempted.
- `AccountTreeCache.reload()` with 500 added ledgers and FY-scoped balances: 0.095s.
- 50k-voucher encrypted report timings: trial balance 0.736s, P&L 0.270s, balance sheet 0.297s, GST summary 0.000s, cash flow 0.951s, stock ageing 0.001s.
- `ReportRepository+Statements.swift` was split into financial-statement and compliance-report extensions, and `ReportsView+Content.swift` report sections were split into focused `ReportsBody+...` extensions without changing `ReportService` cache keys or invalidation behavior.
- Release mechanics re-run on 2026-06-21: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES swift build` passed, `make net-check` reported 0 matches, release build and bundle validation passed, and `Scripts/bundle_selftest.sh` passed for company setup, voucher CRUD, FY lock, reports, backup, and recovery-key restore.

### V3: Later Hardening / Scale Work
- Filesystem-type detection and FAT32-specific backup warnings.
- Thermal-throttling-aware UI behavior.
- `VACUUM` / `ANALYZE` automation and other maintenance jobs.
- Materialized rollups and advanced reporting acceleration.
- Deep UI virtualization and more aggressive memory-load shedding.
- Niche hardware-edge-case protections such as serial-port bounds checks or cosmic-ray-style fault mitigation.

Hidden entry-point rule:
- Conditional or deferred modules must not remain exposed in the shipped release path unless they pass the same gates as core ship.
- Current hidden-entry-point review targets: sidebar routes, command palette items, quick search hits, menu items, and sheet entry points for advanced GST export actions.

## Top 10 Blockers In Execution Order

1. `AVL-P0-011` — replace unchecked financial arithmetic with throwing overflow-safe operations.
2. `AVL-P0-008` — establish exact alternate-UOM quantity representation needed by valuation.
3. `AVL-P0-010` — implement authoritative FIFO and weighted-average valuation with stock layers.
4. `AVL-P0-024` — net each trial-balance account to one closing side.
5. `AVL-P0-025` — reject overlapping financial years and make date lookup deterministic.
6. `AVL-P0-026` — enforce fiscal locks across every dated financial write path.
7. `AVL-P0-030` — enforce company ownership at database and service boundaries.
8. `AVL-P0-027` — fail closed when persisted dates, enums, columns, or values are malformed.
9. `AVL-P0-002` — make voucher numbering gap-free under contention and rollback.
10. `AVL-P0-012` — establish anchored tamper evidence required by cancellation and repair.

Execution queue alignment:

- `Docs/Avelo_Execution_Checklist.md` is the remaining-work queue and groups only open `AVL-*` items into dependency waves.
- Checklist state meanings are:
  - `Implementation remaining`
  - `Proof remaining`
  - `Manual acceptance remaining`
- The current Wave `P0-A` proof-closure queue is: `AVL-P0-012`, `AVL-P0-011`, `AVL-P0-025`, `AVL-P0-026`, `AVL-P0-030`, `AVL-P0-027`, and `AVL-P0-002`.
- The current Wave `P0-B` remaining implementation queue is empty; the wave now contains only proof and manual-acceptance closure work.
- `AVL-P0-003` implementation and automated proof are landed; it remains open only until accountant outstanding/bill-allocation acceptance is executed and recorded.
- `AVL-P0-004` implementation and automated proof are landed; it remains open only until accountant bounced-cheque acceptance is executed and recorded.
- `AVL-P0-009` implementation and automated proof are landed; it remains open only until manufacturing validation acceptance is executed and recorded.
- `AVL-P0-008` implementation and automated proof are landed; it remains open only until accountant unit-conversion acceptance is executed and recorded.
- `AVL-P0-010` implementation and automated proof are landed; it remains open only until accountant valuation acceptance is executed and recorded.
- `AVL-P0-024` implementation and automated proof are landed; it remains open only until accountant trial-balance acceptance is executed and recorded.
- `AVL-P0-019` implementation and automated proof are landed; it remains open only until accountant backdated-stock acceptance is executed and recorded.
- `AVL-P0-001` implementation and automated proof are landed; it remains open only until accountant invoice-rounding acceptance is executed and recorded.
- `AVL-P0-032` implementation and automated proof are landed; it remains open only until accountant voucher-cancel acceptance is executed and recorded.
- `AVL-P0-005` implementation and automated proof are landed; it remains open only until accountant year-close acceptance is executed and recorded.
- `AVL-P0-006` implementation and automated proof are landed; it remains open only until accountant locked-period correction acceptance is executed and recorded.
- `AVL-P0-007` implementation and automated proof are landed; it remains open only until accountant keyboard-entry acceptance is executed and recorded.
- `AVL-P0-028` implementation and automated proof are landed; it remains open only until accountant company-picker preservation acceptance is executed and recorded.
- `AVL-P0-031` implementation and automated proof are landed; it remains open only until operator recovery acceptance is executed and recorded.
- `AVL-P0-029` implementation and automated proof are landed; it remains open only until operator company-create rollback acceptance is executed and recorded.

## Release-Risk Split

| Track | Status | Notes |
| --- | --- | --- |
| V1 | Active | Day-one correctness, restore safety, file-open/save reliability, and launch viability risks stay here until closed. |
| V2 | Deferred until post-launch unless needed to unblock V1 | Merge behavior, stronger backup integrity, at-rest encryption, and broader scale tuning belong here. |
| V3 | Deferred | Edge-case resilience, maintenance automation, and deep scale or hardware hardening belong here. |

## Canonical Readiness Backlog

This is the single normalized readiness catalogue. Existing completed `RB-*` entries below are historical implementation evidence, not proof that Avelo is Ready. An item remains `Open` until its automated proof and manual accountant acceptance both pass. Exact Tally chords are compatibility aliases; current macOS bindings remain supported.

### P0 — Must Fix Before “Ready” (32 open)

| ID | Status | Depends | Requirement | Proof of done |
| --- | --- | --- | --- | --- |
| AVL-P0-001 | Open | None | Deterministic GST round-off ledger for invoice/tax rounding differences, with one authoritative `ROUND_OFF` line derived during posting/edit instead of caller-supplied balancing. | Golden invoices prove balanced postings, deterministic paise allocation, and seeded/migrated `ROUND_OFF` ledger availability; accountant verifies printed totals. |
| AVL-P0-002 | Open | None | Gap-free voucher numbering under concurrent saves and failed transactions. | Contention and rollback tests prove committed numbers are unique, ordered, and never reused. |
| AVL-P0-003 | Open | None | Bill-wise FIFO allocation for partial receipts, payments, advances, and on-account amounts. | Golden bill-settlement fixtures reconcile every allocation and outstanding balance; restore/remap preserves bill references and settlement state. |
| AVL-P0-004 | Open | AVL-P0-003 | Non-destructive bounced-cheque workflow using linked reversals. | Original cheque/voucher remains immutable; persisted cheque metadata survives edit and restore, and linked bounce/re-presentation flows are fully audited. |
| AVL-P0-005 | Open | AVL-P0-025, AVL-P0-026 | Carry locked-FY closing balances into the next FY exactly once, without mutating historical ledger masters, and remove/regenerate that published opening snapshot cleanly on reopen/re-close. | Close/reopen/idempotency fixtures reconcile every ledger to the prior closing balance, later-FY reports use the carried snapshot, and accountant year-close acceptance confirms the workflow. |
| AVL-P0-006 | Open | AVL-P0-026 | Graceful reversal-only correction for locked-FY records, with read-only voucher inspection and an explicit linked reversal path instead of in-place edits. | UI and service tests reject edits without crashing, locked vouchers open read-only, and linked current-period reversals preserve history and numbering. |
| AVL-P0-007 | Open | AVL-P0-002 | Prevent duplicate vouchers from rapid Enter/default-action activation by gating a visible posting attempt to one in-flight submission. | Repeated-key and concurrent-submit tests produce one durable voucher and one audit event, while deliberate later posts still work normally. |
| AVL-P0-008 | Open | AVL-P0-011 | Alternate-UOM conversion using rational/fixed-point quantities, never floating truncation. | Round-trip fixtures cover fractional conversions, residual units, and extreme quantities. |
| AVL-P0-009 | Open | AVL-P0-011 | Detect direct and indirect circular BOMs before costing or expansion. | Persisted BOM definitions reject direct and indirect cycles before write, survive restore, and terminate with an actionable validation error. |
| AVL-P0-010 | Open | AVL-P0-008, AVL-P0-011 | Real FIFO and weighted-average valuation with consumable layers, divide-by-zero handling, and deterministic residual paise. | Golden purchase/sale/return/backdate fixtures reconcile quantity, COGS, and closing value exactly. |
| AVL-P0-011 | Open | None | Throw on overflow in every money/quantity calculation, including BOM, stock, payroll, reports, reconciliation, reductions, absolute values, and `Int64.min` formatting. | Boundary/property tests prove no trap, wrap, saturation, or silent precision loss. |
| AVL-P0-012 | Open | None | Keyed or externally anchored tamper evidence for the audit chain. | Mutation, deletion, insertion, reordering, and whole-chain rewrite simulations are detected. |
| AVL-P0-013 | Open | None | Exclude registry, company databases, WAL, SHM, and recovery artifacts from iCloud sync. | Filesystem metadata checks now cover app-support roots, registry, company files, and restore outputs; clean-device manual storage-policy acceptance is still required before closure. |
| AVL-P0-014 | Open | None | Hold `ProcessInfo` activity assertions during migrations, restore, backup, repair, and long recalculation. | Cancellation and error tests always release assertions; sleep/App Nap QA completes operations safely. |
| AVL-P0-015 | Open | AVL-P0-031 | Run schema migrations off the main thread with progress, cancellation policy, and recovery UI. | Large migration keeps UI responsive and resumes or rolls back safely after interruption. |
| AVL-P0-016 | Open | None | One source of truth for company/router/editor state; no stale UI pointers. | Company-switch, close-window, sheet, and delayed-task stress tests produce no stale writes or nil crashes. |
| AVL-P0-017 | Open | None | Guarantee `sqlite3_finalize`/reset/clear on every prepare, bind, step, cancellation, eviction, and close path. | Fault-injection tests leave no busy statements or leaked handles. |
| AVL-P0-018 | Open | None | Autosave and crash recovery for in-progress vouchers without double-posting. | Kill/relaunch fixtures restore drafts and never convert a draft into a posted voucher automatically. |
| AVL-P0-019 | Open | AVL-P0-010 | Cascade inventory-cost recalculation after backdated insert, edit, reversal, or cancellation. | Downstream valuation/COGS fixtures update deterministically and expose progress/failure state. |
| AVL-P0-020 | Open | None | Reliable `@FocusState` Tab/Shift-Tab/Enter navigation in voucher grids. | Full keyboard matrix passes for first, middle, last, inserted, deleted, and validation-error rows. |
| AVL-P0-021 | Open | None | Locale-aware decimal parsing with unambiguous stored paise. | Indian and comma-decimal locale fixtures round-trip pasted and typed values. |
| AVL-P0-022 | Open | None | GST-compliant invoice/PDF for registered-party (B2B) Sales/Purchase vouchers: mandatory fields, CGST/SGST/IGST/CESS breakdown, HSN/SAC, place of supply, inventory-linked stock detail. B2C (unregistered party), export invoices, credit/debit notes, and RCM are explicitly deferred to follow-on tickets. Signed QR / e-invoice IRN is permanently out of scope: it requires an online call to the government e-invoice portal, which conflicts with R-1 (100% offline, zero network calls) — see `AVL-P1-008`, which stays open but is no longer a dependency of this ticket. | Field-matrix tests (intra-state CGST/SGST, inter-state IGST, CESS, unregistered-party fallback, inventory-linked/non-linked stock detail) and a working UI export button in `VouchersView`; remains open only until accountant B2B tax-invoice acceptance is executed and recorded. |
| AVL-P0-023 | Open | None | Force Indian accounting calendar semantics in IST regardless of device timezone. | Boundary tests cover midnight, DST device zones, leap days, GST periods, and FY transitions. |
| AVL-P0-024 | Open | AVL-P0-011 | Net each trial-balance account to one debit or credit closing side. | ₹100 Dr opening plus ₹40 Cr movement reports ₹60 Dr; authoritative fixtures pass per account. |
| AVL-P0-025 | Open | AVL-P0-023 | Reject overlapping or ambiguous financial years, enforce the rule on FY updates, and use deterministic containing-date lookup that fails closed on corrupt ambiguity. | Create/import/restore tests reject overlap, adjacent accepted years resolve exactly one containing FY, corrupt overlap fixtures fail closed instead of returning `LIMIT 1`, and migrated databases carry both insert/update overlap guards. |
| AVL-P0-026 | Open | AVL-P0-025 | Fiscal lock enforcement for vouchers, lines, opening balances, stock, payroll, banking, and every dated mutation, including update-date validation and restore-installed trigger coverage for migrated databases. | Direct SQL, repository, service, restore, and UI attempts all fail closed outside controlled maintenance, including stock, payroll, bank, opening-balance, and voucher-date mutation fixtures. |
| AVL-P0-027 | Open | None | Fail closed on malformed dates, timestamps, enums, missing columns, invalid booleans, and corrupt persisted values. | Corrupt-row fixtures never become epoch dates, Journal, Debit, FIFO, zero, or empty text. |
| AVL-P0-028 | Open | None | Replace registry `INSERT OR REPLACE` with collision-safe insert/update semantics. | Duplicate name, ID, and filename tests preserve every existing registry row and company file. |
| AVL-P0-029 | Open | AVL-P0-028, AVL-P0-031 | Atomic company creation across file, Keychain, schema, seed data, and registry with compensating cleanup. | Failure at every stage leaves either one usable company or no file/key/registry residue; `seedDefaults` is honored. |
| AVL-P0-030 | Open | None | Enforce same-company ownership through database constraints/triggers plus service/repository validation. | Adversarial cross-company FY/account/item/employee/voucher/bank/order references are rejected at every boundary. |
| AVL-P0-031 | Open | None | Make schema-version reads throwing; never interpret an unreadable database as version zero. | Corrupt, locked, wrong-key, and I/O-failure tests stop before any migration mutation. |
| AVL-P0-032 | Open | AVL-P0-002, AVL-P0-012 | Audit-safe voucher cancellation that preserves the voucher, number, persisted reason/actor/timestamp, linkage, and history. | Cancelled vouchers remain visible, numbers are not reused, reversal linkage and audit evidence persist, reports apply defined treatment, and deletion is unnecessary. |

### P1 — Fix Before Broad Rollout (44 open)

| ID | Status | Depends | Requirement | Proof of done |
| --- | --- | --- | --- | --- |
| AVL-P1-001 | Open | None | GSTR-9/9C reconciliation with traceable differences. | Golden annual-return fixture reconciles filed periods to books. |
| AVL-P1-002 | Open | AVL-P0-022 | RCM self-invoicing and linked tax/payment postings. | Applicable inward-supply fixtures generate compliant documents and journals. |
| AVL-P1-003 | Open | None | E-way bill Part-B update, cancellation, expiry, and vehicle-change state. | API/state fixtures preserve identifiers and audit every transition. |
| AVL-P1-004 | Open | None | PF, ESI, Professional Tax, and payroll rounding/rate-effective calculations. | State/rate/date golden payroll fixtures reconcile payslips and journals. |
| AVL-P1-005 | Open | None | Form 16 and 24Q/26Q filing exports with validation. | Official-schema fixtures validate and reconcile to payroll/TDS ledgers. |
| AVL-P1-006 | Open | AVL-P1-005 | Forms 27Q and 27EQ plus correction/export workflows. | Resident/non-resident and TCS fixtures pass schema validation. |
| AVL-P1-007 | Open | AVL-P0-022 | GSTR-1/1A/IFF, GSTR-3B, GSTR-2B, and IMS accept/reject/pending reconciliation. | Portal-format fixtures round-trip and every ITC decision is traceable. |
| AVL-P1-008 | Open | AVL-P0-022 | E-invoice IRN generation, reporting-window enforcement, cancellation, signed JSON/QR storage, verification, and printing. | Sandbox/fixture lifecycle covers success, duplicate, timeout, retry, cancellation, and late-report rejection. |
| AVL-P1-009 | Open | AVL-P0-011 | Multi-currency books, exchange rates, realized/unrealized forex journals, and revaluation. | Multi-period golden fixtures reconcile base and foreign balances. |
| AVL-P1-010 | Open | AVL-P0-030 | Cost centres with per-line allocation and report reconciliation. | Split-allocation fixtures reconcile vouchers and reports. |
| AVL-P1-011 | Open | AVL-P1-010 | Cost categories for parallel Project/Department-style allocation. | Independent category dimensions reconcile without double counting. |
| AVL-P1-012 | Open | AVL-P0-010 | Godown/transit ledger with transfer ownership and in-transit valuation. | Dispatch/receipt/shortage fixtures preserve total stock and value. |
| AVL-P1-013 | Open | AVL-P0-010 | Expired-batch enforcement with override policy and audit. | Sale/transfer fixtures block or explicitly authorize expired lots. |
| AVL-P1-014 | Open | AVL-P0-009, AVL-P0-010 | By-product and scrap lines in manufacturing vouchers. | BOM production fixtures balance input, output, scrap, and cost allocation. |
| AVL-P1-015 | Open | AVL-P0-010 | Configurable negative-stock valuation and later receipt adjustment. | Negative-to-positive timelines recalculate deterministically. |
| AVL-P1-016 | Open | AVL-P1-007 | Debit/credit-note linkage across GST periods. | Amendment fixtures reconcile original document, note, return period, and IRN state. |
| AVL-P1-017 | Open | AVL-P0-016 | Multi-window company/editor isolation and restoration. | Two-window stress proves no context or draft leakage. |
| AVL-P1-018 | Open | AVL-P0-030 | Optimistic locking for concurrent editors/users. | Stale writes produce merge/conflict UI and never overwrite silently. |
| AVL-P1-019 | Open | AVL-P0-013 | Detect symlinks, external/network drives, and unsupported filesystem semantics. | File-placement matrix warns or rejects according to policy. |
| AVL-P1-020 | Open | AVL-P0-017 | WAL checkpoint scheduling, failure visibility, and bounded WAL growth. | Long-session and crash tests preserve data with bounded sidecars. |
| AVL-P1-021 | Open | AVL-P0-013 | Time Machine registry/company-file consistency check and recovery guidance. | Snapshot-skew fixtures detect mismatched registry/database generations. |
| AVL-P1-022 | Open | None | Strip CSV BOM safely. | UTF-8/UTF-16 BOM fixtures parse without contaminating headers. |
| AVL-P1-023 | Open | None | Standards-compliant CSV nested quotes and embedded delimiters. | RFC-style fixtures preserve exact field content. |
| AVL-P1-024 | Open | None | TSV quoted/embedded line-break handling. | Multiline paste fixtures preserve row and field boundaries. |
| AVL-P1-025 | Open | AVL-P0-016 | Cmd+Z/redo model-view resynchronization for voucher grids. | Undo/redo stress preserves focus, totals, validation, and saved state. |
| AVL-P1-026 | Open | AVL-P0-020 | Create ledger/master mid-voucher through `Alt+C` without losing the draft. | Keyboard flow creates, selects, audits, and returns focus to the originating field. |
| AVL-P1-027 | Open | None | Tally importer with dry run, mapping, resumability, and reconciliation report. | Representative company fixtures import idempotently with explicit exceptions. |
| AVL-P1-028 | Open | AVL-P0-010 | Bank reconciliation using the selected bank leg, signed direction, persisted matches, import fingerprints, and idempotency. | Duplicate imports do not duplicate lines; match/clear/unmatch round-trips reconcile book and bank balances. |
| AVL-P1-029 | Open | AVL-P0-010 | Consumable stock-ageing layers whose buckets sum to on-hand quantity/value. | FIFO consumption fixtures prove no bucket exceeds surviving stock. |
| AVL-P1-030 | Open | AVL-P0-030 | Prevent account-group cycles, cross-company parents, and nature-incompatible hierarchy. | Direct, indirect, imported, and update-cycle fixtures fail before persistence. |
| AVL-P1-031 | Open | None | Checksummed recovery keys with typo-specific errors and versioning. | Single-character mutation fixtures fail before database open. |
| AVL-P1-032 | Open | AVL-P0-012 | Audit FY unlocks, bank changes, inventory orders, masters, repair, exports, printing, signing, and email. | Mutation inventory test proves every financially meaningful action emits one immutable event. |
| AVL-P1-033 | Open | AVL-P0-009, AVL-P0-010 | Replace BOM, bill allocation, cheque, TDS/TCS, and cost-centre stubs with real guarded workflows. | No shipped-path test treats `featureUnavailable` as successful readiness evidence. |
| AVL-P1-034 | Open | AVL-P1-010 | Voucher Classes that expand configured ledgers, tax, freight, and charges deterministically. | Class-version fixtures produce explainable balanced drafts and preserve overrides. |
| AVL-P1-035 | Open | AVL-P0-003 | Simple/advanced ledger interest with rate periods, day-count convention, grace, and posting policy. | Overdue/partial-payment/leap-period fixtures reconcile interest schedules. |
| AVL-P1-036 | Open | None | Comparative report columns for multiple periods (`Alt+N`). | Month/quarter/year columns reconcile individually and as a whole. |
| AVL-P1-037 | Open | AVL-P0-032 | Universal Day Book with every voucher type, inline drill-down, edit/cancel, and date navigation. | Accountant QA completes browse-to-correction without leaving the continuous flow. |
| AVL-P1-038 | Open | AVL-P0-020, AVL-P1-010 | Continuous multi-account voucher grid with cost allocations and no submodal dependency. | Complex payment fixture is completed keyboard-only in one editor. |
| AVL-P1-039 | Open | AVL-P0-012, AVL-P0-031 | Books repair/reindex with immutable dry run, backup requirement, progress, verification, and audit (`Ctrl+Alt+R`). | Corrupt-index fixtures repair safely; unrecoverable corruption leaves original untouched. |
| AVL-P1-040 | Open | AVL-P0-022 | Sales/Purchase Orders, Stock Journal, Physical Stock, Rejection In/Out, Delivery Note, and Receipt Note with fulfilment linkage. | Partial fulfilment, rejection, transit, count, and invoice-conversion fixtures reconcile. |
| AVL-P1-041 | Open | AVL-P0-032 | Voucher/invoice mode and post-dated voucher lifecycle distinct from cheque/PDC state. | Mode switching preserves data; future-dated activation and cancellation follow audited rules. |
| AVL-P1-042 | Open | AVL-P0-022 | Batch printing plus company/printer/voucher-type print profiles. | Party/date batch output and saved-profile render tests pass without missing or duplicated documents. |
| AVL-P1-043 | Open | AVL-P1-042 | DSC PDF signing and structured XML interchange with explicit confirmation. | Certificate/token failure tests are non-destructive; signature and XML schema validation pass. |
| AVL-P1-044 | Open | AVL-P0-020 | Context-aware multi-binding shortcut engine with exact Tally aliases and retained macOS bindings. | Full context/collision matrix proves editor switching, text-input precedence, help discovery, and both binding families. |

### P2 — Post-Launch Polish (20 open)

| ID | Status | Depends | Requirement | Proof of done |
| --- | --- | --- | --- | --- |
| AVL-P2-001 | Open | AVL-P1-042 | Cheque-printing template designer. | Saved templates render accurately on supported paper/printers. |
| AVL-P2-002 | Open | AVL-P1-010 | Budget-versus-actual variance reports. | Period/category fixtures reconcile to ledgers and budgets. |
| AVL-P2-003 | Open | AVL-P0-010 | Orphaned-batch detection and resolution. | Repair fixtures preserve stock/value lineage. |
| AVL-P2-004 | Open | AVL-P1-004 | Leap-year payroll edge cases. | February and rate-transition fixtures pass. |
| AVL-P2-005 | Open | AVL-P0-022 | Regional-script PDF font embedding. | Render/extraction tests preserve glyphs across supported scripts. |
| AVL-P2-006 | Open | AVL-P1-028 | MT940 and CAMT.053 bank imports. | Bank-supplied fixtures round-trip without duplicate transactions. |
| AVL-P2-007 | Open | AVL-P1-028 | Explainable fuzzy reconciliation. | Confidence fixtures never auto-clear ambiguous matches. |
| AVL-P2-008 | Open | AVL-P0-030 | Multi-company consolidation and elimination entries. | Intercompany fixtures reconcile consolidated statements. |
| AVL-P2-009 | Open | None | XLSX export formatting fidelity. | Golden workbook tests verify values, formats, widths, and formulas. |
| AVL-P2-010 | Open | None | Hardware-independent licensing and recovery. | Device replacement/offline-grace fixtures preserve access policy. |
| AVL-P2-011 | Open | AVL-P0-032 | Duplicate voucher (`Alt+2`) with explicit source lineage and fresh number. | Duplicate/edit/save flow never aliases IDs or audit history. |
| AVL-P2-012 | Open | AVL-P0-018 | Narration recall (`Ctrl+R`) with privacy-aware history. | Keyboard flow recalls the correct scoped narration without altering prior vouchers. |
| AVL-P2-013 | Open | AVL-P1-037 | Insert while browsing (`Ctrl+I`) and PgUp/PgDn voucher navigation. | Keyboard-only sequence preserves filters, position, and unsaved-state warnings. |
| AVL-P2-014 | Open | AVL-P0-011 | Inline calculator (`Ctrl+N`) usable from amount fields. | Expression/rounding tests insert paise without floating-point drift. |
| AVL-P2-015 | Open | AVL-P1-036 | Report line zoom (`Alt+Z`). | Drill/return preserves report context and accessibility. |
| AVL-P2-016 | Open | AVL-P0-022 | Direct email with generated PDF attachment (`Alt+M`) and explicit confirmation. | Cancel/auth/retry tests never send twice or silently. |
| AVL-P2-017 | Open | AVL-P1-043 | Legacy ASCII/SDF/HTML exports; XML remains P1. | Documented compatibility fixtures preserve encoding and field semantics. |
| AVL-P2-018 | Open | None | Expand discoverable contextual shortcuts beyond the daily-use compatibility matrix. | Shortcut catalogue and conflict audit pass for every supported screen state. |
| AVL-P2-019 | Open | None | Gateway-style dashboard showing company context, key reports, and menu-tree quick access in the macOS shell. | Accountant QA reaches daily destinations without added navigation depth; accessibility remains native. |
| AVL-P2-020 | Open | None | Separate F11 company capabilities from F12 per-screen behavior/configuration. | Every supported screen exposes contextual configuration while company feature flags remain centrally scoped. |

### Shortcut Compatibility Matrix

| Tally alias | Canonical action | Backlog owner | Current state |
| --- | --- | --- | --- |
| F4/F5/F6/F7/F8/F9 | Contra/Payment/Receipt/Journal/Sales/Purchase | AVL-P1-044 | Opens sheets today; switching is suppressed inside an editor and remains incomplete. |
| Alt+F8 / Alt+F9 | Sales Order / Purchase Order | AVL-P1-040 | Open. |
| Ctrl+F8 / Ctrl+F9 | Credit Note / Debit Note | AVL-P1-040 | Open as aliases; current F10/F11 macOS bindings remain. |
| Alt+F7 | Stock Journal / Physical Stock | AVL-P1-040 | Open. |
| Alt+F5 / Alt+F6 | Receipt/Delivery/Rejection logistics flows | AVL-P1-040 | Open; resolve by active inventory context. |
| Ctrl+V | Voucher/invoice mode | AVL-P1-041 | Open. |
| Alt+C | Create master in field | AVL-P1-026 | Open. |
| Alt+2 | Duplicate voucher | AVL-P2-011 | Open. |
| Ctrl+R | Recall narration | AVL-P2-012 | Open; context must distinguish existing reverse commands. |
| Ctrl+I | Insert voucher while browsing | AVL-P2-013 | Open; context must distinguish narration focus. |
| Alt+X | Audit-safe cancel | AVL-P0-032 | Open. |
| Ctrl+Alt+R | Repair/reindex books | AVL-P1-039 | Open. |
| Ctrl+N | Calculator | AVL-P2-014 | Open; current Cmd+N remains New. |
| PgUp / PgDn | Previous/next voucher | AVL-P2-013 | Open. |
| Alt+F6 | Cost allocation selection | AVL-P1-010 / AVL-P1-011 | Open; allocation context takes precedence over logistics. |
| Alt+Z | Zoom/report detail | AVL-P2-015 | Open. |
| Alt+E | Structured export | AVL-P1-043 / AVL-P2-017 | Open. |
| Alt+M | Confirmed email dispatch | AVL-P2-016 | Open. |
| Alt+S / Ctrl+T | Post-date voucher | AVL-P1-041 | Open. |
| Alt+N | Comparative columns | AVL-P1-036 | Open. |

Binding rules: aliases resolve by the active keyboard context; existing macOS bindings remain valid; plain text input wins unless the active editor explicitly owns the command; email and DSC operations always require confirmation; conflicts must be visible in shortcut help.

## Historical RC Board

The following completed entries document earlier RC work. They do not override the open canonical readiness catalogue above.

| ID | Severity | Status | Checklist Ref | Issue |
| --- | --- | --- | --- | --- |
| RB-001 | P0 | Done | B | Migrate `AccountsViewModel` and remove `AccountsViewModelHolder` |
| RB-002 | P0 | Done | B | Migrate `ReportsViewModel` and remove `ReportsViewModelHolder` |
| RB-003 | P0 | Done | B | Migrate `VouchersViewModel` and remove `VouchersViewModelHolder` |
| RB-004 | P0 | Done | B | Migrate `VoucherEditViewModel` and remove `VoucherEditHolder` |
| RB-005 | P0 | Done | B | Migrate `SettingsViewModel` |
| RB-006 | P0 | Done | B | Migrate `AuditViewModel` and remove `AuditViewModelHolder` |
| RB-007 | P0 | Done | B | Confirm no shipped workflow mixes old and new observation systems |
| RB-008 | P0 | Done | C | Reconcile company and financial-year tables in migration against frozen schema |
| RB-009 | P0 | Done | C | Reconcile account-group and account tables in migration against frozen schema |
| RB-010 | P0 | Done | C | Reconcile voucher and ledger-lines tables in migration against frozen schema |
| RB-011 | P0 | Done | C | Reconcile audit tables in migration against frozen schema, including the frozen allowed-action set |
| RB-012 | P0 | Done | C | Reconcile matching tables in `schema_v1.sql` against frozen schema |
| RB-013 | P0 | Done | C | Confirm `MigrationV001.swift` and `schema_v1.sql` match each other |
| RB-014 | P0 | Done | D | Reconcile `CompanyRepository` and `FinancialYearRepository` against frozen schema/rules |
| RB-015 | P0 | Done | D | Reconcile `AccountRepository` against frozen schema/rules |
| RB-016 | P0 | Done | D | Reconcile `VoucherRepository` against frozen schema/rules |
| RB-017 | P0 | Done | D | Reconcile `AuditRepository` against frozen schema/rules |
| RB-018 | P0 | Done | D | Reconcile `BackupService` and restore path against frozen rules |
| RB-019 | P0 | Done | D | Harden voucher posting against known `P0` defects |
| RB-020 | P0 | Done | D | Harden voucher edit against known `P0` defects |
| RB-021 | P0 | Done | D | Harden voucher reversal against known `P0` defects |
| RB-022 | P0 | Done | D | Verify FY lock enforcement across all shipped write paths |
| RB-023 | P0 | Done | D | Verify audit logging for all financially meaningful actions |
| RB-024 | P0 | Done | D | Verify company isolation |
| RB-025 | P0 | Done | D | Verify restore integrity |
| RB-026 | P1 | Done | E | Review company setup and switching shipped flows |
| RB-027 | P1 | Done | E | Review accounts shipped flow |
| RB-028 | P1 | Done | E | Review voucher list/create/edit/reverse shipped flows |
| RB-029 | P1 | Done | E | Review settings/FY-management shipped flow |
| RB-030 | P1 | Done | E | Review backup/restore shipped flows |
| RB-031 | P1 | Done | F | Validate trial balance totals against seeded and live SQL totals |
| RB-032 | P1 | Done | F | Validate P&L totals against seeded and live SQL totals |
| RB-033 | P1 | Done | F | Validate balance sheet totals against seeded and live SQL totals |
| RB-034 | P1 | Done | F | Validate ledger, day book, GST summary, and outstanding behavior |
| RB-035 | P1 | Done | F | Verify report drill-down opens the correct source voucher |
| RB-036 | P1 | Done | G | Add regression tests for schema-sensitive and accounting-sensitive fixes |
| RB-037 | P1 | Done | I | Run manual accountant-style QA for shipped scope |
| RB-038 | P2 | Done | H | Inventory audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-039 | P2 | Done | H | Payroll audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-040 | P2 | Done | H | Banking audited; scope decision updated from hidden to shipped in the local RC shell |
| RB-041 | P2 | Done | H | Advanced GST export audited and kept deferred from V1 shell entry points |
| RB-043 | P1 | Done | J | Prove promoted inventory, payroll, and banking shell routes behave correctly across sidebar, menu, keyboard, and command palette |
| RB-042 | P2 | Done | J | Run stress, soak, RC, and deployment validation |
| RB-048 | P2 | Done | J | Benchmark harness and 500k stress validation completed with before/after JSON and post-cleanup memory gate proof |

## Completed Board Items

| ID | Severity | Checklist Ref | Completed Item |
| --- | --- | --- | --- |
| RB-D01 | P0 | B | `AppEnvironment`, `AppRouter`, and `WindowState` migrated to `@Observable` |
| RB-D02 | P0 | B | App composition root moved from `environmentObject` to typed environment injection |
| RB-D03 | P0 | B | Shell views migrated to typed environment access |
| RB-D04 | P0 | B | `KeyboardBridge`, `KeyboardRouter`, and `AccountTreeCache` migrated |
| RB-D05 | P0 | B | `OnboardingViewModel` and `DashboardViewModel` migrated |
| RB-D05A | P0 | B | `AccountsViewModel` migrated and `AccountsViewModelHolder` removed |
| RB-D05B | P0 | B | `ReportsViewModel` migrated and `ReportsViewModelHolder` removed |
| RB-D05BB | P0 | B | `VouchersViewModel` migrated and `VouchersViewModelHolder` removed |
| RB-D05BC | P0 | B | `VoucherEditViewModel` migrated and `VoucherEditHolder` removed |
| RB-D05C | P0 | B | `SettingsViewModel` migrated |
| RB-D05D | P0 | B | `AuditViewModel` migrated and `AuditViewModelHolder` removed |
| RB-D05E | P0 | B | Shipped release path no longer mixes old and new observation systems |
| RB-D06 | P0 | C | Silent-delete schema violation on `avelo_ledger_lines.voucher_id` removed |
| RB-D06A | P0 | C | Company and financial-year migration tables reconciled to frozen schema |
| RB-D06B | P0 | C | Account-group and account migration tables reconciled to frozen schema |
| RB-D06C | P0 | C | Voucher and ledger-lines migration tables reconciled to frozen schema |
| RB-D06D | P0 | C | Audit migration table reconciled to frozen schema, including allowed action constraint |
| RB-D06E | P0 | C | `schema_v1.sql` reconciled to frozen schema for current checklist tables |
| RB-D06F | P0 | C | `MigrationV001.swift` and `schema_v1.sql` now match for the current checklist scope |
| RB-D07A | P0 | D | `CompanyRepository` and `FinancialYearRepository` reconciled against frozen schema/rules |
| RB-D07B | P0 | D | `AccountRepository` reconciled against frozen schema/rules |
| RB-D07C | P0 | D | `VoucherRepository` reconciled against frozen schema/rules |
| RB-D07D | P0 | D | `AuditRepository` reconciled against frozen schema/rules |
| RB-D07E | P0 | D | `BackupService` and restore path reconciled against frozen rules |
| RB-D07 | P0 | D | Voucher post no longer swallows account-usage update failures |
| RB-D07F | P0 | D | Voucher posting hardened for validation, account usage, and audit snapshot correctness |
| RB-D07G | P0 | D | Voucher edit hardened for locked-FY rejection and full audit snapshots |
| RB-D07H | P0 | D | Voucher reversal hardened for locked-FY flow, duplicate reversal blocking, and audit snapshots |
| RB-D07I | P0 | D | FY lock enforcement verified across shipped voucher write paths |
| RB-D07J | P0 | D | Audit logging verified for voucher lifecycle and FY lock actions |
| RB-D07K | P0 | D | Company isolation verified for shipped voucher reads and writes |
| RB-D07L | P0 | D | Backup/restore integrity verified with end-to-end roundtrip and preserved audit history |
| RB-D08 | P1 | F | Dashboard summary logic corrected to use real account codes and report totals |
| RB-D09 | P1 | E | App brought back to clean build after shell migration |
| RB-D10 | P1 | E | Automated suite kept green after shell migration |
| RB-D11 | P1 | E | Company setup flow kept green after onboarding migration |
| RB-D12 | P0 | G | Malformed UUIDs now fail loudly in shipped repository, registry, and report decode paths, with regression tests guarding the behavior |
| RB-D13 | P0 | G | Silent-delete regression coverage added to prove voucher deletes do not cascade ledger lines |
| RB-D14 | P0 | G | Account-usage update failures now fail closed and are guarded by repository and transaction rollback tests |
| RB-D15 | P0 | G | Voucher post, edit, and reversal `P0` hardening now have rollback and invariant regression coverage |
| RB-D16 | P0 | G | FY lock enforcement is guarded by service-level tests for post, edit, and reversal behavior |
| RB-D17 | P0 | G | Audit write expectations are guarded by voucher lifecycle and restore tests |
| RB-D18 | P0 | G | Company isolation is guarded by shipped voucher read/write tests |
| RB-D19 | P0 | G | Backup/restore roundtrip is guarded by end-to-end restore tests |
| RB-D20 | P1 | F | Trial balance totals are now guarded by seeded expected-value and live SQL reconciliation tests |
| RB-D21 | P1 | F | P&L totals are now guarded by seeded expected-value and live SQL reconciliation tests on the real default chart shape |
| RB-D22 | P1 | F | Balance sheet totals are now guarded by seeded expected-value and live SQL reconciliation tests for the shipped balance-sheet model |
| RB-D23 | P1 | F | Day book behavior is guarded by range and ordering tests on seeded report activity |
| RB-D24 | P1 | F | Outstanding report now uses the correct debtor/creditor account codes and is guarded by direction and as-of tests |
| RB-D25 | P1 | F | GST summary sign handling is fixed and guarded by seeded bucket/date-range tests |
| RB-D26 | P1 | F | Report date-boundary coverage now guards trial balance, day book, and GST filtering against later activity leakage |
| RB-D27 | P1 | G | Targeted report reconciliation and behavior tests now cover trial balance, P&L, balance sheet, day book, GST summary, outstanding, and report date boundaries |
| RB-D28 | P1 | F | Ledger report behavior is now guarded by running-balance, date-range, and source-voucher-linkage tests |
| RB-D29 | P0 | V1 | Company open and backup paths now honor registry-tracked SQLite file names, preserve legacy `id.sqlite` fallback, and fail clearly when a registered file is missing |
| RB-D30 | P1 | E | Company create/open and company-switch flow behavior is now guarded by environment-level tests that prove usable context setup, router reset, and visible company-state swap |
| RB-D31 | P1 | E | Restore flow now auto-opens the restored company and is guarded by environment-level proof that a restored company lands in a usable context |
| RB-D32 | P1 | E | Open-company, new-account, new-voucher, and edit-voucher shipped UI paths now surface typed errors instead of silently swallowing repository/service failures |
| RB-D33 | P1 | G | Account and voucher validation now fail with internal validation errors instead of silently accepting database lookup failures, guarded by failure-mode tests |
| RB-D34 | P2 | G | Report repository query paths now throw instead of silently degrading aggregate calculations to zero when the database query fails |
| RB-D35 | P1 | D | Company file delete cleanup now fails loudly on removal errors and is guarded by regression coverage for registered and legacy file removal |
| RB-D36 | P1 | D | Backup export now reports file-system errors cleanly when the destination path is invalid and is guarded by regression coverage |
| RB-D37 | P1 | F | Report drill-down routing now explicitly targets the edit-voucher sheet for tapped report rows and is guarded by regression coverage |
| RB-D38 | P2 | J | Added a reproducible `Scripts/bundle.sh` app-bundle path, validated `dist/Avelo.app` launches locally, and fixed the shipped invalid SF Symbol on the dashboard quick actions |
| RB-D39 | P2 | J | Added automated RC stress coverage for voucher volume and repeated report generation, and proved both checks green |
| RB-D40 | P2 | J | Expanded RC local-failure coverage for startup degradation, close-company cleanup, backup replacement failure, and duplicate-restore rejection |
| RB-D41 | P2 | J | Added repeatable bundle validation with ad-hoc signing and structural verification for the local RC distribution artifact |
| RB-D42 | P1 | J | Promoted inventory, payroll, and banking routes now work across shipped shell entry points, with keyboard routing regression coverage and aligned menu shortcuts |
| RB-D43 | P1 | B | Inventory, payroll, and banking now use the same `@Observable` shipped-shell pattern as the rest of the core release path, and `make rule-audit` keeps those promoted modules excluded from the shipped-surface R-16 audit |
| RB-D44 | P2 | J | Added a repeatable bundled-app launch smoke check and proved `dist/Avelo.app` launches and stays alive locally when run outside the sandbox |
| RB-D45 | P2 | J | Restore now has explicit regression coverage for a non-writable destination company directory, further narrowing the remaining local file-handling RC risk |
| RB-D46 | P1 | I/J | Added an integrated accountant RC flow test that creates and opens a real company, creates an account, posts/edits/reverses vouchers, locks FY, validates reports, and round-trips backup/restore end to end |
| RB-D47 | P1 | D/J | Restore now succeeds even when the source company contains locked financial years, by suspending locked-FY voucher/ledger triggers only during the controlled restore remap window |
