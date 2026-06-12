# Avelo Module Checklist

The file-by-file gap map and per-slice acceptance criteria. Every Swift file in the project is listed here. When a pass is complete, every file in that pass's slice is checked off in code review.

Out of scope for this checklist: cloud sync, remote login, remote protection, and other network-dependent features.

Legend: `[ ]` pending · `[x]` done · `[-]` deferred (with reason) · `[!]` blocked on something

---

## Pass 0 — Docs

- [x] `Docs/Avelo_Master_PRD.md` — product, screens, fields, errors, shortcuts
- [x] `Docs/Avelo_Architecture.md` — layers, naming, dependency rules
- [x] `Docs/Avelo_Rules.md` — non-negotiables
- [x] `Docs/Avelo_Schema.md` — SQLite schema, constraints, indexes
- [x] `Docs/Avelo_Module_Checklist.md` — this file
- [x] `Docs/Avelo_Naming_Freeze.md` — every name locked

## Pass 1 — Shared

### Theme
- [x] `Shared/Theme/AppColors.swift` — semantic colors (success, error, warning, debit, credit, sidebar bg, etc.)
- [x] `Shared/Theme/AppTypography.swift` — SF Pro / monospaced digit stack, sizes
- [x] `Shared/Theme/AppMetrics.swift` — corner radii, padding, row heights, sidebar widths

### Components
- [x] `Shared/Components/EmptyStateView.swift`
- [x] `Shared/Components/SearchBar.swift`
- [x] `Shared/Components/FilterChip.swift`
- [x] `Shared/Components/StatusBadge.swift`
- [x] `Shared/Components/ConfirmationDialog.swift`
- [x] `Shared/Components/MoneyTextField.swift`
- [x] `Shared/Components/AccountPicker.swift`
- [x] `Shared/Components/KeyboardShortcutMap.swift`
- [x] `Shared/Components/ErrorBanner.swift`

## Pass 2 — Models

- [x] `Core/Models/Company.swift`
- [x] `Core/Models/FinancialYear.swift`
- [x] `Core/Models/AccountGroup.swift`
- [x] `Core/Models/Account.swift`
- [x] `Core/Models/VoucherType.swift`
- [x] `Core/Models/Voucher.swift`
- [x] `Core/Models/LedgerLine.swift`
- [x] `Core/Models/InventoryItem.swift`
- [x] `Core/Models/StockMovement.swift`
- [x] `Core/Models/PayrollEmployee.swift`
- [x] `Core/Models/PayrollEntry.swift`
- [x] `Core/Models/AuditEvent.swift`
- [x] `Core/Models/ReportResult.swift`
- [x] `Core/Models/CompanyRegistry.swift`
- [x] `Core/Models/VoucherDraft.swift` — input-only struct used by ViewModels
- [x] `Core/Models/BannerKind.swift` — UI feedback model

## Pass 3 — Database

- [x] `Core/Database/SQLiteDatabase.swift` — C API wrapper
- [x] `Core/Database/DatabaseManager.swift` — actor; registry + per-company handles
- [x] `Core/Database/MigrationRunner.swift`
- [x] `Core/Database/SchemaVersion.swift`
- [x] `Core/Database/SeedLoader.swift`
- [x] `Core/Database/BackupService.swift`
- [x] `Core/Database/RestoreService.swift`
- [x] `Core/Database/Migrations/MigrationV001.swift` — full schema

## Pass 4 — Resources

- [x] `Resources/SQL/schema_v1.sql` — source of truth used by `MigrationV001`
- [x] `Resources/Seed/DefaultChartOfAccounts.json` — 13 groups + 28 ledgers + 10 voucher types

## Pass 5 — Repositories

- [x] `Core/Repositories/CompanyRepository.swift`
- [x] `Core/Repositories/FinancialYearRepository.swift`
- [x] `Core/Repositories/AccountRepository.swift`
- [x] `Core/Repositories/AccountGroupRepository.swift`
- [x] `Core/Repositories/VoucherRepository.swift`
- [x] `Core/Repositories/LedgerLineRepository.swift`
- [x] `Core/Repositories/VoucherSequenceRepository.swift`
- [x] `Core/Repositories/InventoryRepository.swift`
- [x] `Core/Repositories/PayrollRepository.swift`
- [x] `Core/Repositories/AuditRepository.swift`
- [x] `Core/Repositories/ReportRepository.swift`
- [x] `Core/Repositories/RegistryRepository.swift`
- [x] `Core/Repositories/BankReconciliationRepository.swift`

## Pass 6 — Services

- [x] `Core/Services/CompanyService.swift`
- [x] `Core/Services/FinancialYearService.swift`
- [x] `Core/Services/AccountService.swift`
- [x] `Core/Services/VoucherService.swift`
- [x] `Core/Services/TransactionService.swift` — thin wrapper over VoucherService for double-entry writes
- [x] `Core/Services/ReportService.swift`
- [x] `Core/Services/InventoryService.swift`
- [x] `Core/Services/PayrollService.swift`
- [x] `Core/Services/GSTService.swift`
- [x] `Core/Services/BankReconciliationService.swift`
- [x] `Core/Services/AuditService.swift`
- [x] `Core/Services/ValidationService.swift`

## Pass 7 — Validation

- [x] `Core/Validation/ValidationError.swift`
- [x] `Core/Validation/ValidationResult.swift`
- [x] `Core/Validation/Validator.swift` — protocol
- [x] `Core/Validation/VoucherDraftValidator.swift`
- [x] `Core/Validation/AccountInputValidator.swift`
- [x] `Core/Validation/FinancialYearInputValidator.swift`
- [x] `Core/Validation/CompanyInputValidator.swift`
- [x] `Core/Validation/PayrollDraftValidator.swift`
- [x] `Core/Validation/StockMovementValidator.swift`
- [x] `Core/Utilities/Currency.swift`
- [x] `Core/Utilities/IndianFinancialYear.swift`
- [x] `Core/Utilities/DateFormatters.swift`
- [x] `Core/Utilities/VoucherNumberGenerator.swift`
- [x] `Core/Utilities/FiscalLockChecker.swift`

## Pass 8 — App shell

- [x] `App/AveloApp.swift`
- [x] `App/AppEnvironment.swift`
- [x] `App/AppRouter.swift`
- [x] `App/SidebarDestination.swift`
- [x] `App/WindowState.swift`
- [x] `App/RootView.swift`
- [x] `App/SidebarView.swift`
- [x] `App/CompanyPickerView.swift`
- [x] `App/ErrorBannerHost.swift`

## Pass 9 — Features

### Onboarding
- [x] `Features/Onboarding/CompanySetupView.swift`
- [x] `Features/Onboarding/FinancialYearSetupView.swift`
- [x] `Features/Onboarding/OpeningBalancesView.swift`
- [x] `Features/Onboarding/CompanySetupViewModel.swift`
- [x] `Features/Onboarding/FinancialYearSetupViewModel.swift`
- [x] `Features/Onboarding/OpeningBalancesViewModel.swift`

### Dashboard
- [x] `Features/Dashboard/DashboardView.swift`
- [x] `Features/Dashboard/DashboardViewModel.swift`

### Accounts
- [x] `Features/Accounts/AccountsListView.swift`
- [x] `Features/Accounts/AccountEditorView.swift`
- [x] `Features/Accounts/AccountGroupEditorView.swift`
- [x] `Features/Accounts/AccountsViewModel.swift`
- [x] `Features/Accounts/AccountEditorViewModel.swift`

### Vouchers
- [x] `Features/Vouchers/VoucherListView.swift`
- [x] `Features/Vouchers/VoucherEntryView.swift`
- [x] `Features/Vouchers/VoucherEditorRowView.swift`
- [x] `Features/Vouchers/VoucherViewModel.swift`
- [x] `Features/Vouchers/VoucherEntryViewModel.swift`
- [x] `Features/Vouchers/VoucherListViewModel.swift`
- [x] `Features/Vouchers/InventoryLinkPromptView.swift`

### Reports
- [x] `Features/Reports/ReportsHomeView.swift`
- [x] `Features/Reports/LedgerReportView.swift`
- [x] `Features/Reports/TrialBalanceView.swift`
- [x] `Features/Reports/ProfitLossView.swift`
- [x] `Features/Reports/BalanceSheetView.swift`
- [x] `Features/Reports/GSTSummaryView.swift`
- [x] `Features/Reports/DayBookView.swift`
- [x] `Features/Reports/OutstandingView.swift`
- [x] `Features/Reports/ReportDrillDownView.swift`
- [x] `Features/Reports/ReportsViewModel.swift`

### Inventory
- [x] `Features/Inventory/InventoryHomeView.swift`
- [x] `Features/Inventory/StockItemListView.swift`
- [x] `Features/Inventory/StockItemEditorView.swift`
- [x] `Features/Inventory/StockMovementView.swift`
- [x] `Features/Inventory/InventoryViewModel.swift`
- [x] `Features/Inventory/StockItemEditorViewModel.swift`
- [x] `Features/Inventory/StockMovementViewModel.swift`

### Payroll
- [x] `Features/Payroll/PayrollHomeView.swift`
- [x] `Features/Payroll/EmployeeListView.swift`
- [x] `Features/Payroll/EmployeeEditorView.swift`
- [x] `Features/Payroll/SalaryVoucherView.swift`
- [x] `Features/Payroll/PayrollViewModel.swift`
- [x] `Features/Payroll/EmployeeEditorViewModel.swift`
- [x] `Features/Payroll/SalaryVoucherViewModel.swift`

### Banking
- [x] `Features/Banking/BankReconciliationView.swift`
- [x] `Features/Banking/BankReconciliationViewModel.swift`

### Audit
- [x] `Features/Audit/AuditLogView.swift`
- [x] `Features/Audit/AuditFilterView.swift`
- [x] `Features/Audit/AuditViewModel.swift`

### Settings
- [x] `Features/Settings/SettingsView.swift`
- [x] `Features/Settings/CompanyInfoView.swift`
- [x] `Features/Settings/BackupRestoreView.swift`
- [x] `Features/Settings/SettingsViewModel.swift`

## Pass 10 — Project root

- [x] `README.md`
- [x] `Docs/Avelo_ASSEMBLY.md`
- [x] `.gitignore`

---

## Per-slice acceptance criteria

### Slice 1 — Foundation
- [x] App launches and shows the company picker.
- "New Company" wizard collects name, address, GSTIN/PAN, base currency, and a financial year (start, end, books-begin date) and a default chart of accounts choice.
- On confirm, a `.sqlite` file is created at `Application Support/Avelo/Companies/<uuid>.sqlite` and seeded with the full schema + default voucher types + default groups + default ledgers.
- The registry DB records the company.
- The dashboard shell renders with the company name, active FY, and a "no data yet" empty state.
- [x] "Open Backup" works.
- [x] Switching the FY in the toolbar updates the active FY.
- [x] Company Info menu exposes local company actions: select company, create company, backup, restore, and close company.
- [x] New Company wizard captures every field-level input required by the spec.

### Slice 2 — Accounts
- Accounts screen lists groups and ledgers in a tree.
- Add ledger under a group; opening balance and side captured.
- Edit ledger; edits to opening balance are allowed only on the first FY.
- Disable ledger; disabled ledgers do not appear in pickers but still appear in historical reports.
- Add group; reorder via sort_order.
- [x] F11 company-features panel exposes local accounting and inventory toggles in one place.
- [x] F12 configuration exposes local app settings in one place, including data paths and voucher-entry behavior.
- [x] Bill-wise Adjustments support `New Ref`, `Agst Ref`, `Advance`, and `On Account`.
- [x] Batch-wise tracking captures manufacture date and expiry date.
- [x] Zero-valued entries support free samples and gifts without breaking inventory posting.

### Slice 3 — Vouchers
- [x] Voucher list with filters: FY, type, date range, party, narration contains.
- [x] Voucher entry with all 10 types, live debit/credit/diff footer, Tab/Enter shortcuts, party picker, narration.
- [x] Save posts the voucher inside a single DB transaction; audit event is written.
- [x] Edit a posted voucher in an open FY.
- [x] Reverse a posted voucher; the reversal voucher has opposite lines and a `reversal_of_id` link.
- [x] Locked FY rejects any write at the trigger level.
- [x] Accounting voucher variants explicitly cover contra, payment, receipt, journal, sales, purchase, debit note, and credit note entry flows.
- [x] Inventory vouchers explicitly cover purchase order, sales order, receipt note, delivery note, rejection in, rejection out, stock journal, and physical stock.

### Slice 4 — Reports
- [x] Ledger report: account + period; running balance in paise.
- [x] Trial balance: all accounts, debit total, credit total, diff column.
- [x] P&L: income minus expense, broken into sections.
- [x] Balance sheet: assets vs liabilities + equity, group hierarchy respected.
- [x] GST summary: month picker, input vs output, CGST/SGST/IGST/cess, net payable.
- [x] Day book: chronological voucher list.
- [x] Drill-down: any row in any report jumps to the source voucher (open in read-only editor).

### Slice 5 — Inventory
- [x] Toggle inventory on/off in Settings.
- CRUD on stock items; choose valuation method.
- [x] Record stock in (purchase, opening) and stock out (sale, issue) with explicit qty and unit cost.
- After saving a `sales` or `purchase` voucher, prompt to record stock movement; user confirms and posts.
- [x] Stock valuation report (FIFO or WA per item) is available.
- [x] Stock master coverage includes stock groups, stock categories, units of measure, and godowns.
- [x] Bill of Materials supports assembled stock items with component breakdowns.
- [x] Physical Stock vouchers support manual inventory counting and reconciliation.
- [x] Stock Journal vouchers support inter-godown transfers and stock adjustments.

### Slice 6 — Banking, backup, audit
- [x] Bank account identified by `is_bank_account = 1`.
- [x] Reconciliation view shows uncleared bank book entries and accepts statement date + amount matches.
- [x] Mark cleared; clears with timestamp.
- [x] Backup export to chosen `.avelobackup` (zip of the SQLite file + sidecar manifest).
- [x] Restore from `.avelobackup` creates a new company in the picker.
- [x] Audit log view: filters by entity, action, date range; shows before/after JSON for each event.

### Slice 7 — Payroll
- [x] Employee CRUD; termination via end date.
- [x] Salary voucher: pick employee + month; pre-fills gross from base salary; user enters deductions; net is auto-computed; saves as a single voucher with Salary Expense Dr / Cash or Bank Cr.
- [x] Salary register per month per employee.

### Slice 8 — Hardening
- [x] Voucher templates: save current draft as a template, load template into a new draft.
- [x] Last-used-account sort in account picker.
- [x] Multi-line paste (TSV) parses into lines.
- [x] Dark mode respected.
- [x] Full keyboard shortcut help dialog.
- [x] App icon set (placeholder; user replaces later).
- [x] Keyboard shortcuts cover F1 through F12 and the app-level navigation shortcuts listed in the spec.
- [x] Full field-level master coverage is reconciled against the spec for company, group, ledger, stock item, voucher, financial-year, inventory, and GST screens.
