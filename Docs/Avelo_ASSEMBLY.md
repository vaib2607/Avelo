# Avelo — Assembly

This document lists every file in the project and its role. Path is relative to the repo root.

## Top level

- `README.md` — user-facing build / run / data location summary.
- `Docs/Avelo_ASSEMBLY.md` — this file.

## Docs/

Authoritative product and engineering spec. Read these in order if you're new.

- `Avelo_Master_PRD.md` — fields, screens, error strings, shortcuts.
- `Avelo_Architecture.md` — layers, MVVM, `SQLiteDatabase` API.
- `Avelo_Rules.md` — non-negotiables (offline, paise, double-entry, FY locks, audit immutability, reversal-not-delete).
- `Avelo_Schema.md` — frozen SQLite schema.
- `Avelo_Module_Checklist.md` — per-file completion tracker.
- `Avelo_Naming_Freeze.md` — authoritative type / method / table / column names.

## Avelo/

### App/

SwiftUI entry point and DI.

- `AveloApp.swift` — `@main`. Sets up commands, env, hosts `RootView`.
- `AppEnvironment.swift` — DI container, owns `DatabaseManager`, `AppRouter`, `RegistryRepository`, `BackupService`, current `CompanyContext`.
- `AppRouter.swift` — sidebar selection + sheet / alert presentation.
- `SidebarDestination.swift` — enum for the 9 modules (Dashboard, Vouchers, Accounts, Reports, Inventory, Payroll, Banking, Audit, Settings) with title / SF Symbol / ⌘1–9 shortcut.
- `WindowState.swift` — split-view visibility, ledger account, report selection.
- `RootView.swift` — shows `CompanyPickerView` when no company is open, otherwise a `NavigationSplitView` with `SidebarView` and the active module.
- `SidebarView.swift` — sidebar listing current company + FY + module links.
- `CompanyPickerView.swift` — first-launch / app-level picker; lists known companies.
- `ErrorBannerHost.swift` — top overlay for transient banners and busy spinner.

### Core/Database/

The only files that call `sqlite3_*`.

- `SQLiteDatabase.swift` — connection wrapper, parameter binding, `NSRecursiveLock`, `write { tx in ... }` BEGIN IMMEDIATE / COMMIT / ROLLBACK, in-transaction depth counter so nested `execute` / `query` calls work.
- `DatabaseManager.swift` — actor that owns the registry + per-company file paths, opens connections, runs migrations.
- `MigrationRunner.swift` — `Migration` protocol + runner that compares `PRAGMA user_version` to the latest `SchemaVersion`.
- `SchemaVersion.swift` — `current = 1`.
- `SeedLoader.swift` — loads `DefaultChartOfAccounts.json` (or built-in fallback) and seeds the default chart, voucher types, and per-type sequences.
- `BackupService.swift` — `await export(companyId:to:)` zips the `.sqlite` + manifest with SHA-256.
- `RestoreService.swift` — `await restore(from:)` validates checksum, copies to a new uuid, registers.
- `Migrations/MigrationV001.swift` — full v1 schema in a Swift string literal (also duplicated in `Resources/SQL/schema_v1.sql`).

### Core/Models/

Plain Codable structs, one file per aggregate.

- `Company.swift` — `Company` + `InventoryLinkMode`.
- `FinancialYear.swift` — `FinancialYear` + `FYStatus`.
- `AccountGroup.swift` — `AccountGroup` + `AccountNature`.
- `Account.swift` — `Account` + `OpeningBalanceSide`.
- `VoucherType.swift` — `VoucherType` + `VoucherType.Code` enum (10 cases).
- `Voucher.swift` — `Voucher` + `LedgerLine` + `LedgerSide` + `VoucherDraft` + `VoucherDraft.Line` + `VoucherDraft.Mode`.
- `InventoryItem.swift` — `InventoryItem` + `StockMovement` + `InventoryItem.MovementType`.
- `PayrollEmployee.swift` — `PayrollEmployee` + `PayrollEntry`.
- `AuditEvent.swift` — `AuditEvent` + `AuditAction` + `AuditRepository.Filter`.
- `ReportResult.swift` — all 7 report structs (`TrialBalance`, `LedgerReport`, `ProfitLoss`, `BalanceSheet`, `GstSummary`, `DayBook`, `Outstanding`, `StockValuation`).
- `CompanyRegistry.swift` — `CompanyRegistryEntry` + `BackupManifest`.

### Core/Repositories/

Thin SQL on top of `SQLiteDatabase`. One per aggregate.

- `CompanyRepository.swift`
- `FinancialYearRepository.swift`
- `AccountGroupRepository.swift`
- `AccountRepository.swift`
- `VoucherRepository.swift` — `Filter` struct; `markReversal` for the reversal chain.
- `LedgerLineRepository.swift` — batch insert / delete by voucher.
- `VoucherSequenceRepository.swift` — atomic per-(company, FY, type) sequence using `avelo_voucher_sequences`.
- `InventoryRepository.swift` — `runningBalance(itemId:asOf:)` returns `ItemBalance`.
- `PayrollRepository.swift`
- `AuditRepository.swift` — append-only insert + filterable list.
- `RegistryRepository.swift` — points at `avelo_registry.sqlite`.
- `BankReconciliationRepository.swift` — `bookBalance`, `statementLines`, `candidateVouchers`, `clearStatementLine`.
- `ReportRepository.swift` — all 7 reports; `signedOpening` for P&L.

### Core/Services/

Use cases. Compose repositories + validators + audit. Write paths open one `db.write { tx in ... }` per call.

- `CompanyService.swift` — `create(...)` is static and async; opens the new file, runs seed, registers.
- `FinancialYearService.swift` — list, create, lock, unlock, close.
- `AccountService.swift` — list / create / update / disable; ensures group is a leaf.
- `VoucherService.swift` — `post`, `edit`, `reverse`, `validate`, `loadDraft`; reversal posts flipped lines as a fresh voucher and links both directions.
- `TransactionService.swift` — thin wrapper used by the UI for posting.
- `ReportService.swift` — convenience filter builder.
- `InventoryService.swift` — items, archive, movements, link to ledger account.
- `PayrollService.swift` — employees, monthly salary posting.
- `GSTService.swift` — summary, return builder, GSTR-1 CSV.
- `BankReconciliationService.swift` — import, reconcile, clear.
- `ValidationService.swift` — façade over all validators + static PAN / GSTIN helpers.
- `AuditService.swift` — `record(action:entityType:entityId:snapshotBefore:snapshotAfter:reason:)`; takes `Encodable?` so any model encodes directly.

### Core/Validation/

Pure functions; no DB writes.

- `AppError.swift` — `AppError` (userMessage, codes), `SQLiteError`, `InventoryPromptContext`.
- `ValidationError.swift` — `ValidationError` + `ValidationErrorCode`.
- `ValidationResult.swift` — `enum .valid / .invalid([ValidationError])`.
- `CompanyInputValidator.swift` — name + PAN regex; static `isValidPAN`.
- `FinancialYearInputValidator.swift` — `start < end`, `booksBegin >= start`, overlap detection.
- `AccountInputValidator.swift` — code/name/leaf group checks; static `isValidGSTIN`.
- `VoucherDraftValidator.swift` — 6 debit=credit rules, FY date, type-specific required party / narration.
- `PayrollDraftValidator.swift` — `paidDays <= workingDays`, non-negative.
- `StockMovementValidator.swift` — qty > 0, rate >= 0.

### Core/Utilities/

- `Currency.swift` — `rupeesToPaise`, `paiseToRupees`, `parseRupeeInput`, Indian-grouping `formatPaise`, `formatAmountInput`.
- `DateFormatters.swift` — `dd/MM/yyyy` for users, `yyyy-MM-dd` for ISO date, `yyyy-MM-ddTHH:mm:ss.SSSZ` for ISO timestamp, `MM/yyyy` for GST periods.
- `IndianFinancialYear.swift` — `detect()`, `start(for:)`, `end(for:)`, label.
- `VoucherNumberGenerator.swift` — `formatNumber(prefix:fy:next:)` returns `PREFIX/yy-yy/00001`.
- `FiscalLockChecker.swift` — `isLocked(financialYearId:)` reads `avelo_financial_years.is_locked`.

### Shared/

UI primitives.

- `Theme/AppColors.swift` — semantic colors.
- `Theme/AppTypography.swift` — fonts.
- `Theme/AppMetrics.swift` — spacing + corner radii.
- `Components/EmptyStateView.swift`
- `Components/SearchBar.swift`
- `Components/FilterChip.swift`
- `Components/StatusBadge.swift` — `.success / .warning / .neutral / .info`.
- `Components/ConfirmationDialog.swift`
- `Components/MoneyTextField.swift` — `TextField` wrapper that uses Indian grouping.
- `Components/AccountPicker.swift` — searchable `Picker`.
- `Components/KeyboardShortcutMap.swift` — single place to read `KeyboardShortcutMap.shortcut(for:)`.
- `Components/ErrorBanner.swift` — `BannerKind` + `ErrorBanner` view.

### Resources/

- `SQL/schema_v1.sql` — duplicate of v1 schema for reference.
- `Seed/DefaultChartOfAccounts.json` — 13 groups, 34 ledgers, 10 voucher types.

## Features/

### Onboarding/

- `OnboardingViewModel.swift` — drives the new-company form.
- `NewCompanySheet.swift` — name, PAN, GSTIN, FY dates, inventory toggle.
- `OpenCompanySheet.swift` — searchable list of registered companies.
- `BackupSheet.swift` — `NSSavePanel` to write a `.zip` backup.
- `RestoreSheet.swift` — `NSOpenPanel` to import a backup.
- `AboutSheet.swift` — version + offline pledge.
- `PreferencesSheet.swift` — `AppStorage`-backed date / currency / confirm toggles.

### Dashboard/

- `DashboardViewModel.swift` — pulls cash, bank, receivables, payables, month sales/purchases, GST payable, stock value, trial balance, monthly P&L, recent vouchers.
- `DashboardView.swift` — KPI grid + cash position + monthly P&L table + recent vouchers.

### Accounts/

- `AccountsViewModel.swift` — list, filter, disable.
- `AccountsView.swift` — `HSplitView` (groups left, accounts right).
- `NewAccountSheet.swift` — form, leaf-group picker, GSTIN optional.

### Vouchers/

- `VouchersViewModel.swift` — filter, search, type filter, date range.
- `VouchersView.swift` — `Table` of vouchers with Edit / Reverse actions.
- `VoucherEditViewModel.swift` — line-editing state + balance + validation.
- `NewVoucherSheet.swift` — full editor (date, party, reference, narration, lines).
- `EditVoucherSheet.swift` — same shell, loads existing.
- `ReverseVoucherSheet.swift` — reason + new voucher with flipped lines.

### Reports/

- `ReportsViewModel.swift` — runs the active report on filter / date changes.
- `ReportsView.swift` — sidebar of report types + main panel per report.

### Inventory/

- `InventoryViewModel.swift` — items, archived toggle, search.
- `InventoryView.swift` — `Table` with Movement… and Archive actions.
- `NewItemSheet.swift` — code, name, unit, opening qty + rate, GST, HSN.
- `StockMovementSheet.swift` — type, qty, rate, notes.
- `ManageInventorySheet.swift` — placeholder (real settings live in Settings).

### Payroll/

- `PayrollViewModel.swift` — employees + entries.
- `PayrollView.swift` — `VSplitView` (employees top, entries bottom).
- `NewEmployeeSheet.swift` — identity + bank + salary components.
- `PostSalarySheet.swift` — month picker, working/paid days, OT, deductions.
- `ManagePayrollSheet.swift` — placeholder.

### Banking/

- `BankingViewModel.swift` — bank-account filter, reconcile.
- `BankingView.swift` — picker, as-of date, summary + matched / unmatched tables.
- `ImportStatementSheet.swift` — CSV paste (`date,amount,narration`) → `BankReconciliationService.importStatement`.

### Audit/

- `AuditViewModel.swift` — search, entity type filter.
- `AuditView.swift` — `HSplitView` (event list left, before/after JSON right).

### Settings/

- `SettingsViewModel.swift` — financial years + lock/unlock/close.
- `SettingsView.swift` — company, FY table, preferences, about.
- `NewFinancialYearSheet.swift` — label + dates.
- `LockFinancialYearSheet.swift` — reason + lock.
- `CloseFinancialYearSheet.swift` — confirm + close.

## Data flow at a glance

```
SwiftUI View
   ▼ @StateObject ViewModel
   ▼ Service.useCase(...)
       ▼ Repository.sql(...)
           ▼ SQLiteDatabase.execute / query
   ▼ AuditService.record(...) inside the same db.write
```

- All write paths use `db.write { tx in ... }` (BEGIN IMMEDIATE).
- Triggers in `MigrationV001` block any write that would violate FY lock, group-must-be-leaf, audit immutability, or voucher ↔ FY date.
- Reversal creates a new voucher with flipped lines; the original is never deleted. UI hides the action on rows that are themselves reversals.
- `Currency` always formats paise through `Int64` math; the only `Double` is for stock quantities.
- No file under `Avelo/` imports anything from the network stack (`URLSession`, `Network.framework`, etc.) and no `Process` / `Shell` calls exist anywhere in the project.
