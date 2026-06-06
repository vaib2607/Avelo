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

To produce an `.app` bundle, run the helper in `Scripts/bundle.sh` (provided) which assembles `Mally.app` from the build output.

## Run

```bash
.build/release/Mally
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
