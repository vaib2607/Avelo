# Avelo Operator Guide

## Backup and Restore

- Use the app’s backup flow to export a company into an `.avelobackup` file.
- Backups include a manifest version, schema version, company identity, database byte count, and SHA-256 checksum.
- Restores are staged before import. The app verifies the manifest, checksum, byte count, schema version, company identity, and foreign keys before replacing any local company file.
- Restores are name-checked before import. If a company already exists with the same name, rename or remove the existing company first.
- If a restore fails, the app keeps the registry and original company file untouched and removes the staged restore copy.

## Encryption

- File-backed company databases are encrypted at rest with the embedded SQLCipher/CommonCrypto build.
- Encryption is fully local. There is no cloud key service, network recovery flow, or remote unlock path.
- If an encrypted company file cannot be unlocked or is corrupt, restore a known-good `.avelobackup`; the app should fail before opening the company store.

## Reports

- Trial balance, profit and loss, balance sheet, GST summary, day book, ledger, outstanding, stock valuation, cash flow, stock ageing, and invoice-wise GSTR-1 CSV export are available from Reports.
- Report filters are date-sensitive. If a report looks empty, confirm the financial year and date range first.
- Search is intentionally limited in this release and appears only where it is already supported in the UI.

## Inventory

- Purchase order and sales order pending-line visibility is available from the inventory service layer.
- Stock ageing and reorder alerts are available when inventory is enabled.
- When inventory is disabled, inventory reporting and alerts intentionally return no operational data.

## Search

- Search is available in selected screens such as reports, settings, and company open.
- If a screen does not expose search, that is intentional for this release and does not indicate missing data.

## What Is Not Included Yet

- Group-company consolidation
- GST portal/API upload or online filing
- Cloud sync, remote key recovery, or network backup
- UUIDv7 migration for time-sortable identifiers
