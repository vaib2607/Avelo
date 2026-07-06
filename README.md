# Avelo

Offline accounting for macOS.

Native Swift 5.9 + SwiftUI, raw SQLite/SQLCipher C APIs, no external Swift packages, no network calls. All data lives on your Mac under `~/Library/Application Support/Avelo/`.

## Quick start

Use one first-run path:

```bash
cd ~/Developer/Avelo
make setup
```

What you should see:
- Swift 5.9+ is detected from Xcode Command Line Tools.
- The package builds without blocking `ModuleCache`, `org.swift.swiftpm`, or `sandbox_apply` permission failures.
- The full test suite passes.
- `dist/Avelo.app` is created and ready to open.

Then launch the app:

```bash
open dist/Avelo.app
```

What you should see:
- Avelo opens as a normal macOS app.
- On a fresh Mac, Gatekeeper may require right-clicking the app and choosing **Open** once.

If you want the full local proof set after bootstrap:

```bash
make verify
```

What you should see:
- Rule audit passes.
- Tests pass.
- Bundle validation passes.
- The bundled self-test prints `SELFTEST OK`.

### Alternatives

- `make dev`
  What you should see: the debug app launches from `.build/debug/Avelo`.
- `make test`
  What you should see: the full `AveloTests` suite completes with repo-local SwiftPM caches.
- `make bundle`
  What you should see: a signed local bundle appears at `dist/Avelo.app`.

### Upgrading from earlier local workflows

- Prefer `make test`, `make verify`, or `./Scripts/swiftw.sh ...` over raw `swift build` and `swift test` when your machine restricts `~/Library` or `~/.cache`.
- The repo now keeps SwiftPM caches and scratch data under `.swift-dev/` and `.build/swiftpm-scratch/` so first-run permissions are deterministic.
- Use `make verify` as the single release-confidence command instead of manually chaining build, test, bundle, and self-test steps.

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

If raw `swift` commands fail because your machine blocks writes to `~/Library/org.swift.swiftpm` or `~/.cache/clang`, rerun the same step through `make` or `./Scripts/swiftw.sh`. Avelo ships a repo-local fallback for SwiftPM caches.

## Build

```bash
make bundle
```

What you should see:
- The release binary builds with repo-local SwiftPM caches.
- `Created .../dist/Avelo.app` prints at the end.

To build without bundling:

```bash
./Scripts/swiftw.sh build -c release
```

What you should see:
- `Build complete!` prints with no blocking cache-permission failures.

The local RC bundle is ad-hoc signed, so on a fresh Mac you may need to right-click the app and choose Open the first time to clear the Gatekeeper warning.

Validate the bundle structure and signature:

```bash
./Scripts/validate_bundle.sh
```

What you should see:
- The script exits cleanly with no signature or structure errors.

Smoke-launch the bundled app and confirm it stays up long enough to count as a valid local artifact:

```bash
./Scripts/launch_smoke.sh
```

What you should see:
- The app launches and remains alive for the smoke window.

Or run the repeatable local RC proof set in one go:

```bash
make verify
```

This runs the rule audit, full test suite, release build, bundle assembly, bundle validation, and bundled self-test. The GUI launch smoke check remains separate because it needs a normal local app-launch context.

For a bundled-binary accountant-flow self-check without GUI interaction:

```bash
./Scripts/bundle_selftest.sh
```

What you should see:
- Output that includes `SELFTEST OK` and a balanced trial balance.

## Run

```bash
make dev
```

What you should see:
- The debug binary launches locally.

Or launch the bundled app directly:

```bash
open dist/Avelo.app
```

What you should see:
- The app opens from `dist/Avelo.app`.

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

For the developer loop, proof-set commands, and benchmark interpretation, see `Docs/DX.md`.

## Contributing

Start with `CONTRIBUTING.md` for branch naming, commit style, test expectations, and pull request requirements.

Copyright © 2026 Karbonteck. All rights reserved.
