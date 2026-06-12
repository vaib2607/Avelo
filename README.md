# Avelo

Offline accounting for macOS.

Native Swift 5.9 + SwiftUI, raw `import SQLite3`, no third-party packages, no network calls. All data lives on your Mac under `~/Library/Application Support/Avelo/`.

## At A Glance

| Area | Status |
| --- | --- |
| Core engine | `v1.1` hardening for speed, accuracy, and reliability |
| Benchmark focus | cold launch, company switching, voucher posting, reports, backup/restore, 500k stress |
| Math model | paise-exact, deterministic rounding, reconciliation checks |
| Storage | local SQLite, per-company files, no network dependency |

## Release Focus

- `v1.1` hardens the core engine for speed, accuracy, and reliability.
- Release ID: `019ebdbd-6540-7fb3-ac41-9f4fcd59c0f2`
- Benchmark validation now covers cold launch, company switching, voucher posting, reports, backup/restore, and 500k-voucher stress runs on the same machine and dataset.
- Paise-exact accounting remains the priority: no drift, deterministic rounding, and reconciliation checks on the core report paths.

## What Changed

### New or Expanded

- Reconciled the pinned `Docs/Avelo_Module_Checklist.md` end-to-end and checked off the remaining items.
- Expanded New Company onboarding to capture address fields, base currency, FY dates, and default chart selection.
- Added FY switching from the toolbar.
- Confirmed and documented voucher list filters, voucher entry flow, save/edit/reverse behavior, and locked FY protections.
- Added bill-wise adjustments support.
- Added batch-wise inventory tracking with manufacture and expiry dates.
- Added zero-valued inventory entry support for free samples and gifts.
- Confirmed inventory voucher coverage, including purchase order, sales order, receipt note, delivery note, rejection in/out, stock journal, and physical stock.
- Implemented Bill of Materials support with assembly and component breakdown storage.
- Confirmed banking reconciliation, backup/restore, audit log, payroll employee CRUD, salary voucher flow, and salary register coverage.
- Added voucher template save/load support.
- Added TSV paste support for voucher lines.
- Confirmed keyboard shortcut help and F1 through F12 plus navigation shortcut coverage.

### Already There

- Core offline accounting flow, multi-company storage, paise-based double-entry posting, reports, backup/restore, audit logging, and financial-year locking.
- Local SQLite storage with no network dependency.
- Existing shipped workflows remain intact while the surface widened around them.

### Why It Is Better

- The README now matches the actual product surface, so contributors can scan the current scope without hunting through docs.
- The app covers more of the offline accounting workflow without needing network features.
- Data entry is faster and more Tally-like for recurring vouchers and stock operations.
- The current benchmark proof shows the 500k stress path improving throughput and report latency while staying inside the cleanup target.

## Highlights

| Capability | Included |
| --- | --- |
| Multi-company | Separate `.sqlite` file per company, selectable at launch |
| Accounting | `Int64` paise double-entry with Indian currency formatting |
| Vouchers | Journal, Payment, Receipt, Contra, Purchase, Sales, Credit Note, Debit Note |
| Reports | Trial Balance, P&L, Balance Sheet, GST Summary, Day Book, Ledger, Outstanding, Stock Valuation |
| Inventory | Stock groups, categories, units, godowns, batch tracking, physical stock, stock journal, BOM support |
| Payroll | Employees and monthly salary postings |
| Banking | CSV import and reconciliation against posted vouchers |
| Audit | Append-only ledger of every write |
| Financial years | Locking and closing with overlap protection |
| Backup / restore | Portable `.zip` backups with SHA-256 manifest |
| Speedups | Cached statements, report caching, transaction batching, tighter cleanup under stress |
| Entry helpers | Voucher templates, TSV line paste, and function-key shortcuts |

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
    └── *.zip
```

## Docs

See `Docs/Avelo_Master_PRD.md` for the product spec, and `Docs/Avelo_Architecture.md` for the layer map. `Docs/Avelo_ASSEMBLY.md` lists every file and what it does.
