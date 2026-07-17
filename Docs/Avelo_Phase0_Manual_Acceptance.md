# Avelo Phase 0 Manual Acceptance

## Purpose and evidence identity

This is the canonical human acceptance record required before Phase 0 closes. Automated tests, source inspection, and agent-authored QA notes cannot mark these rows accepted.

Run all applicable sections against one unchanged release candidate. Capture its identity first:

```bash
./Scripts/phase0_evidence.sh dist/Avelo.app
```

Copy the output below. A changed executable checksum invalidates prior acceptance.

States are `PASS`, `FAIL`, `BLOCKED`, and `NOT RUN`. Only the named human tester may record `PASS`.

| Artifact field | Result |
|---|---|
| Tester name and role | NOT RUN |
| Date/time/timezone | NOT RUN |
| Mac model, CPU, memory, macOS | NOT RUN |
| App version/build and SHA-256 | NOT RUN |
| Signing identity and Team ID | NOT RUN |
| Notarization/stapling | NOT RUN |
| Install source and prior version | NOT RUN |

## A. Accountant acceptance

### A1 — Company, FY, and account selection

1. Create a company and FY; verify shell, dashboard, reports, and voucher editor show the same context.
2. Create and switch to a second company repeatedly; verify no account, voucher, report filter, sheet, or route leaks.
3. Verify Payment/Receipt primary fields contain only Cash-in-Hand, Bank Accounts, and Bank OD descendants.
4. Verify Sales/Purchase fields use their full group ancestry and customer/supplier/dual-role policy.
5. Create an eligible ledger with Alt+C; verify the draft and focus survive and the ledger is selected.
6. Create an ineligible ledger; verify it is not selected and the reason is visible.
7. Regroup or disable a selected account; verify the retained value remains visible with an explanation until replaced.

Expected: picker visibility and service rejection agree; display names never define account meaning. Covers `AVL-P0-016`, `028`, `029`, `033`, and `037`.

### A2 — Voucher keyboard and posting

1. Complete Journal, Payment, Receipt, Contra, Sales, Purchase, Credit Note, and Debit Note keyboard-only.
2. Exercise first, middle, last, inserted, deleted, and validation-error rows with Tab, Shift-Tab, Return, and Escape.
3. Verify Return advances/adds and never posts; Command-Return posts/saves.
4. Command-Return an invalid voucher; verify the exact failing field receives visible focus and an actionable error.
5. Correct it and activate submission repeatedly; verify exactly one voucher posts.
6. Verify native text selection, copy/paste, undo, Return, and Escape retain editor precedence.
7. Kill/relaunch with an unposted draft; verify recovery never posts automatically.

Expected: predictable focus, no lost draft, balanced persisted effect, one durable action per activation. Covers `AVL-P0-002`, `007`, `018`, `020`, and `021`.

### A3 — Bills, cheques, corrections, and audit

1. Allocate and partially settle a bill, reverse settlement, and reconcile outstanding balance and lineage.
2. Deposit, bounce, and re-present a cheque; verify linked vouchers, statuses, reasons, and register totals.
3. Edit an unlocked voucher and inspect before/after audit details.
4. Cancel with a reason; verify the number stays reserved, linked reversal exists, and reports follow defined treatment.
5. Lock the FY; verify post/edit rejection and use the linked open-period correction path without rewriting history.
6. Review representative audit events for company/FY, account, voucher, bill, cheque, inventory, export, backup, and restore.
7. Use a disposable tamper fixture and verify company open fails closed.

Expected: non-destructive history and one understandable audit event per mutation. Covers `AVL-P0-003`–`006`, `012`, `025`, `032`, and `034`.

### A4 — Reports, tax documents, and dates

1. Reconcile Trial Balance, P&L, Balance Sheet, Ledger, Day Book, Cash Flow, GST, and Outstanding to source vouchers.
2. Verify per-account Trial Balance netting and later-FY carried openings.
3. Test FY/GST boundaries, leap day, and midnight with the Mac set to a non-Indian timezone.
4. Create intra/inter-state B2B invoices with tax and round-off; reconcile voucher, reports, PDF, and extracted totals.
5. Verify legal names, GST details, inventory lines, multi-page pagination, and valid zero/negative display.

Expected: every number derives from books and survives drill-down/printing. Covers `AVL-P0-001`, `022`, `023`, `024`, and `027`.

### A5 — Inventory baseline

1. Disable inventory and verify all sidebar/menu/palette/search/shortcut/sheet/deep-link/report/service entry points disappear or reject access, including after company switching.
2. Verify only manual linkage and explicit item-invoice workflows are visible.
3. Enter base/alternate-unit, FIFO/weighted-average, negative-stock, and backdated insert/reversal/replacement cases.
4. Reconcile quantity, value, downstream COGS, stock valuation, and reports.
5. Create valid and cyclic BOMs; verify list/edit behavior and cycle rejection.

Expected: exact quantities, deterministic valuation, explicit stock effects, and no capability bypass. Covers `AVL-P0-008`–`010`, `019`, `033`, and `035`.

## B. Operator acceptance

### B1 — Backup, restore, keys, and corruption

1. Back up a populated company and verify the file, manifest, and visible completion state.
2. Restore on another Mac/user account with the recovery key; verify source IDs are absent and drafts are discarded with notice.
3. Reconcile company/FY identity, counts, balances, inventory, reports, and audit chain.
4. Test wrong key, corrupt manifest, checksum mismatch, truncation, collision, and interrupted restore.
5. Verify each failure preserves the valid original and cleans staging artifacts.
6. Open an unreadable/corrupt company and verify typed recovery guidance, not silent fallback or repair.

Expected: valid old or new state, never partial state. Covers `AVL-P0-013`, `029`, `030`, `031`, and `036`.

### B2 — Migration, sleep, storage, and resources

1. Upgrade representative supported old databases while observing progress and responsiveness.
2. Interrupt at controlled migration boundaries and verify a valid old or new schema.
3. Sleep/wake during backup, restore, migration, and recalculation; verify completion or explicit recovery.
4. Verify documented backup-exclusion and Time Machine guidance for databases and staging paths.
5. Soak company switching, reports, backup/restore, and correction while observing memory, handles, and SQLite statements.

Expected: no partial migration, stale state, busy handles, runaway growth, or App Nap corruption. Covers `AVL-P0-014`, `015`, and `017`.

## C. Accessibility, appearance, PDF, and print

1. Complete company/account/voucher/report/backup/restore workflows with VoiceOver.
2. Verify names, values, roles, grouping, error relationships, and icon-only action labels.
3. Verify visible focus and non-color-only status in light, dark, increased-contrast, and reduced-motion settings.
4. Resize every shipped workspace from minimum supported size through full screen.
5. Verify empty, loading, error, locked, disabled, migration, and large-data states.
6. Preview, save, and physically print representative invoice, voucher, and report PDFs; reconcile identity, pages, totals, fonts, clipping, and printer output.

Expected: complete workflows remain understandable without a mouse, color, or visual-only status.

## D. Distribution and clean-machine acceptance

1. Build the final artifact with approved Developer ID identity, hardened runtime, and reviewed entitlements.
2. Notarize that exact artifact, staple it, and pass strict `codesign` and Gatekeeper `spctl` checks.
3. Verify the downloaded checksum matches the retained release checksum.
4. Install and launch on a clean supported Mac without developer tools.
5. Upgrade from the prior release; verify migration and book reconciliation.
6. Exercise company creation, voucher posting, reports, backup/restore, quit/relaunch, and Gatekeeper launch.
7. Verify release notes, support/incident owner, recovery guidance, retained rollback artifact, and no-downgrade schema policy.

Expected: the final downloadable artifact—not a development bundle—is Gatekeeper accepted and preserves books across install and upgrade.

## Final sign-off

| Area | State | Tester | Evidence / defects |
|---|---|---|---|
| Accountant A1–A5 | NOT RUN | — | — |
| Operator B1–B2 | NOT RUN | — | — |
| Accessibility/visual/print C | NOT RUN | — | — |
| Distribution/clean machine D | BLOCKED — no Developer ID identity installed on 2026-07-17 | — | `security find-identity -v -p codesigning` returned 0 valid identities |

Phase 0 closes only when every row is `PASS`, every failure is fixed and re-run on the final artifact, and the release board references this completed record.
