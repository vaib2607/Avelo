# Avelo Operator Guide

## Backup and Restore

- Use the app’s backup flow to export a company into an `.avelobackup` file.
- Restores are name-checked before import. If a company already exists with the same name, rename or remove the existing company first.
- If a restore fails, the app keeps the original company untouched and writes a failure trail in the logs.

## Reports

- Trial balance, profit and loss, balance sheet, GST summary, day book, ledger, outstanding, and stock valuation are available from Reports.
- Report filters are date-sensitive. If a report looks empty, confirm the financial year and date range first.
- Search is intentionally limited in this release and appears only where it is already supported in the UI.

## Search

- Search is available in selected screens such as reports, settings, and company open.
- If a screen does not expose search, that is intentional for this release and does not indicate missing data.

## What Is Not Included Yet

- Purchase order and sales order tracking
- Cash flow or funds flow statements
- Stock ageing and reorder-level alerts
- Group-company consolidation
- Invoice-wise GSTR-1 portal upload data
- Encryption at rest

