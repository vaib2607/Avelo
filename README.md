# Avelo

Offline accounting for macOS.

Native Swift 5.9 + SwiftUI, raw SQLite/SQLCipher C APIs, no external Swift packages, no network calls. All data lives on your Mac under `~/Library/Application Support/Avelo/`.

## Screenshots

![Dashboard](appscreenshotformarketing/Generated%20image%201.png)

![Vouchers](appscreenshotformarketing/Generated%20image%202.png)

![Reports](appscreenshotformarketing/Generated%20image%203.png)

## At A Glance

| Area | Status |
| --- | --- |
| Core engine | `v1.1` hardening for speed, accuracy, and reliability |
| Benchmark focus | cold launch, company switching, voucher posting, reports, backup/restore, 500k stress |
| Math model | paise-exact, deterministic rounding, reconciliation checks |
| Storage | local SQLCipher-encrypted per-company files, no network dependency |

## Release Focus

- `v1.1` hardens the core engine for speed, accuracy, and reliability.
- Benchmark validation now covers cold launch, company switching, encrypted voucher posting, reports, backup/restore, and large-voucher stress runs on the same machine and dataset.
- Paise-exact accounting remains the priority: no drift, deterministic rounding, and reconciliation checks on the core report paths.
- App-managed company databases are encrypted at rest with per-company random keys stored in Keychain. Recovery keys are user-custody credentials for restoring encrypted backups on another Mac.

## What Changed

### New or Expanded

- Reconciled the pinned `Docs/Avelo_Module_Checklist.md` for the current shipped shell and separated deferred accounting work from shipped scope.
- Expanded New Company onboarding to capture address fields, base currency, FY dates, and default chart selection.
- Added FY switching from the toolbar.
- Confirmed and documented voucher list filters, voucher entry flow, save/edit/reverse behavior, and locked FY protections.
- Added PDF tax invoice export for Sales/Purchase vouchers with company letterhead, GSTIN, and line-item rendering.
- Added bill-wise adjustments support.
- Added batch-wise inventory tracking with manufacture and expiry dates.
- Added zero-valued inventory entry support for free samples and gifts.
- Confirmed inventory voucher coverage, including purchase order, sales order, receipt note, delivery note, rejection in/out, stock journal, and physical stock.
- Implemented Bill of Materials support with assembly and component breakdown storage.
- Confirmed banking reconciliation, backup/restore, audit log, payroll employee CRUD, salary voucher flow, and salary register coverage.
- Added voucher template save/load support.
- Added TSV paste support for voucher lines.
- Confirmed keyboard shortcut help and F1 through F12 plus navigation shortcut coverage.
- Added SQLCipher at-rest encryption for app-managed company databases, per-company Keychain keys, recovery-key restore, and legacy database migration coverage.
- Hardened backup/restore with manifest version checks, SHA-256 and byte-count verification before restore open/copy, temp-file staging, and repeated restore soak coverage.
- Added encryption-aware benchmark tests with explicit thresholds for 10k/100k voucher posting, report generation, and large account-tree reload.
- Split report repository and report UI sections into focused files without changing report calculations or cache keys.

### Deferred / Not Yet Shipped

- Purchase order and sales order workflow visibility across pending receipts and deliveries.
- Cross-company consolidation and group-company reporting.
- Reorder-level reporting.

### Already There

- Core offline accounting flow, multi-company storage, paise-based double-entry posting, reports, backup/restore, audit logging, and financial-year locking.
- Local encrypted SQLite storage with no network dependency.
- Existing shipped workflows remain intact while the surface widened around them.

### Why It Is Better

- The app covers more of the offline accounting workflow without needing network features.
- Data entry is faster and more Tally-like for recurring vouchers and stock operations.
- The current benchmark proof shows the 500k stress path improving throughput and report latency while staying inside the cleanup target.

## Highlights

| Capability | Included |
| --- | --- |
| Multi-company | Separate `.sqlite` file per company, selectable at launch |
| Accounting | `Int64` paise double-entry with Indian currency formatting |
| Vouchers | Journal, Payment, Receipt, Contra, Purchase, Sales, Credit Note, Debit Note |
| Reports | Trial Balance, P&L, Balance Sheet, GST Summary, Day Book, Ledger, Outstanding, Stock Valuation, Cash Flow, Stock Ageing |
| Inventory | Stock groups, categories, units, godowns, batch tracking, physical stock, stock journal, BOM support |
| Payroll | Employees and monthly salary postings |
| Banking | CSV import and reconciliation against posted vouchers |
| Audit | Append-only ledger of every write |
| Financial years | Locking and closing with overlap protection |
| Backup / restore | Portable encrypted `.avelobackup` files with SHA-256 manifest and recovery-key restore |
| Speedups | Cached statements, report caching, transaction batching, tighter cleanup under stress |
| Entry helpers | Voucher templates, TSV line paste, and function-key shortcuts |

## Current Benchmark Proof

Latest encrypted benchmark run on `v1.1-dev`:

| Benchmark | Result | Baseline / threshold |
| --- | ---: | --- |
| `postBatch` 10k vouchers | `5.226s` | baseline `7.858s`, +15% threshold `9.037s` |
| `postBatch` 100k vouchers | `97.805s` | baseline `92.505s`, +15% threshold `106.381s` |
| `AccountTreeCache.reload()` with 500+ ledgers | `0.095s` | threshold `2.000s` |
| 50k trial balance | `0.736s` | threshold `8.000s` |
| 50k P&L | `0.270s` | threshold `8.000s` |
| 50k balance sheet | `0.297s` | threshold `8.000s` |
| 50k cash flow | `0.951s` | threshold `8.000s` |

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ Command Line Tools (Swift 5.9+)
- No Xcode project file is required; build with `swift build` or open the source tree in Xcode as a Swift Package

## Build

```bash
cd ~/Developer/Avelo
swift build -c release
```

To produce an `.app` bundle, first build the release binary, then run the helper in `Scripts/bundle.sh`, which assembles `Avelo.app` from the build output.

```bash
swift build -c release
./Scripts/bundle.sh
```

The assembled app bundle is written to `dist/Avelo.app`.

The local RC bundle is ad-hoc signed, so on a fresh Mac you may need to right-click the app and choose Open the first time to clear the Gatekeeper warning.

Validate the bundle structure and signature:

```bash
./Scripts/validate_bundle.sh
```

Smoke-launch the bundled app and confirm it stays up long enough to count as a valid local artifact:

```bash
./Scripts/launch_smoke.sh
```

Or run the repeatable local RC proof set in one go:

```bash
make rc-local
```

This runs the rule audit, full test suite, release build, bundle assembly, and bundle validation. The GUI launch smoke check remains a separate step because it needs a normal local app-launch context.

For a bundled-binary accountant-flow self-check without GUI interaction:

```bash
./Scripts/bundle_selftest.sh
```

## Run

```bash
.build/release/Avelo
```

Or launch the bundled app:

```bash
open dist/Avelo.app
```

## Where data lives

```
~/Library/Application Support/Avelo/
├── avelo_registry.sqlite
├── Companies/
│   ├── <uuid-1>.sqlite
│   ├── <uuid-2>.sqlite
│   └── ...
└── Backups/
    └── *.avelobackup
```

Company files are encrypted. Keys are stored in the macOS Keychain for the local Mac; keep the shown recovery key somewhere safe if the company needs to be restored on a different machine. Backups include encrypted database bytes, not the key.

## Docs

See `Docs/Avelo_Master_PRD.md` for the product spec, `Docs/Avelo_Architecture.md` for the layer map, and `Docs/Avelo_Release_Board.md` for the current hardening board and benchmark numbers.

Copyright © 2026 Karbonteck. All rights reserved.
