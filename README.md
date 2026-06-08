# Mally

Offline accounting for macOS. Native Swift 5.9 + SwiftUI, raw `import SQLite3`, no third-party packages, no network calls. All data lives on your Mac under `~/Library/Application Support/Mally/`.

## Highlights

- **Multi-company**: each company is a separate `.sqlite` file. Pick from a list at launch.
- **Double-entry** posting with `Int64` paise; Indian currency formatting (`1,18,000.00`).
- **Vouchers**: Journal, Payment, Receipt, Contra, Purchase, Sales, Credit Note, Debit Note.
- **Reports**: Trial Balance, P&L, Balance Sheet, GST Summary, Day Book, Ledger, Outstanding, Stock Valuation.
- **Inventory**: optional per company; stock movements link to vouchers.
- **Payroll**: employees + monthly salary postings.
- **Banking**: import CSV statements, reconcile against posted vouchers.
- **Audit log**: append-only ledger of every write.
- **Financial year** locking and closing with overlap protection.
- **Backup / restore** as portable `.zip` with SHA-256 manifest.

## Requirements

- macOS 14 (Sonoma) or later.
- Xcode 15+ Command Line Tools (Swift 5.9+). The project does not use Xcode project files; build with `swift build` or open the source tree in Xcode as a Swift Package.

## Build

```bash
cd ~/Developer/Mally
swift build -c release
```

To produce an `.app` bundle, first build the release binary, then run the helper in `Scripts/bundle.sh`, which assembles `Mally.app` from the build output.

```bash
swift build -c release
./Scripts/bundle.sh
```

The assembled app bundle is written to `dist/Mally.app`.

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
.build/release/Mally
```

Or launch the bundled app:

```bash
open dist/Mally.app
```

## Where data lives

```
~/Library/Application Support/Mally/
├── mally_registry.sqlite
├── Companies/
│   ├── <uuid-1>.sqlite
│   ├── <uuid-2>.sqlite
│   └── ...
└── Backups/
    └── *.zip
```

## Docs

See `Docs/Mally_Master_PRD.md` for the product spec, and `Docs/Mally_Architecture.md` for the layer map. `ASSEMBLY.md` lists every file and what it does.
