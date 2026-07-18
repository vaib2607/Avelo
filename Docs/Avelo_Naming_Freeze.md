# Avelo Naming Freeze

This file locks compatibility-sensitive names. It is not an imaginary inventory of every type, method, view, or column in the repository. Only names explicitly listed here are frozen.

Conventions:

- Swift types: `PascalCase`
- Swift members: `camelCase`
- SQL tables/columns/indexes/triggers: `snake_case`
- persisted enum raw values: exactly the strings declared by the model and migration
- migration types: `MigrationV###`

A rename is one change containing code, tests, persistence/backfill or compatibility policy, and this document. A SQL rename also updates `Avelo_Schema.md`, restore/remap policy, schema-drift tests, and every supported upgrade path.

## 1. Application and shared state

```text
AveloApp
AppEnvironment
AppRouter
RouterSheet
RouterAlert
SidebarDestination
WindowState
ReportSelection
CompanyContext
BannerKind
BannerPayload
ErrorBannerHost
KeyboardBridge
KeyboardRouter
KeyboardCommand
```

`SidebarDestination` cases:

```text
dashboard, vouchers, accounts, reports, inventory,
gst, payroll, banking, audit, settings
```

Theme namespaces are `AppColors`, `AppMetrics`, and `AppTypography`. The singular name `AppColor` is not valid.

## 2. Core domain names

Identity-bearing and persisted domain types:

```text
Company
CompanyRegistryEntry
BackupManifest
FinancialYear
AccountGroup
Account
VoucherType
Voucher
LedgerLine
VoucherDraft
VoucherEntryDraft
VoucherTemplate
VoucherItemLine
InventoryItem
StockMovement
InventoryOrder
InventoryOrderLine
InventoryReorderLevel
BillOfMaterials
BOMComponent
BillAllocation
Cheque
PayrollEmployee
PayrollEntry
AuditEvent
CostCentre
CostCategory
Budget
```

There is no separate `Transaction` domain type. A posted accounting transaction is a `Voucher` plus its related rows.

Exact arithmetic names:

```text
Currency
CheckedMath
ExactQuantity
SignedExactQuantity
AlternateUnitDefinition
```

## 3. Persisted enum names and raw values

### Voucher and ledger

```text
VoucherType.Code:
  journal, sales, purchase, payment, receipt,
  contra, creditNote, debitNote, opening, payroll

VoucherStatus:
  open, cancelled

EntrySide:
  debit, credit

OpeningBalanceSide:
  debit, credit
```

`LedgerSide` is the compatibility typealias for `EntrySide`.

### Company and inventory

```text
InventoryLinkMode:
  manual, autoPrompt, autoSilent

ValuationMethod:
  fifo, weightedAverage

GSTTaxability:
  taxable, exempt, nilRated

MovementType Swift cases / SQL values:
  stockIn / in
  stockOut / out
  adjustment / adjustment
```

The `autoSilent` name is frozen for database compatibility even while the mode is unavailable for production under `AVL-P0-035`.

### AuditAction

```text
companyCreated, companyUpdated,
financialYearCreated, financialYearLocked, financialYearClosed,
financialYearUnlocked, financialYearReopened,
accountCreated, accountUpdated, accountDisabled,
accountGroupCreated, accountGroupUpdated, accountGroupDeleted,
voucherPosted, voucherEdited, voucherReversed, voucherCancelled,
chequeBounced, chequeRepresented,
openingBalancePosted,
stockItemCreated, stockItemUpdated, stockItemDisabled,
stockMovementPosted, stockMovementReversed,
payrollEmployeeCreated, payrollEmployeeUpdated, payrollEmployeeTerminated,
salaryPosted,
backupExported, backupImported,
companySwitched, financialYearSwitched,
bankStatementImported, bankStatementLineCleared,
inventoryOrderCreated, inventoryOrderFulfilled, inventoryOrderStatusChanged,
inventoryReorderLevelSet,
billOfMaterialsCreated, billOfMaterialsUpdated, voucherTemplateSaved,
gstReportExported, invoicePDFExported, inventoryCostAllocated, itemInvoiceReturnPosted
```

This list reflects current persisted raw values, not adequate production coverage. Any future action name must be added through a forward migration and frozen here before use. Missing action families and service coverage remain `AVL-P0-034`.

### ValidationErrorCode

```text
voucherDebitCreditMismatch, voucherTooFewLines, voucherZeroAmountLine,
voucherDuplicateAccount, voucherAccountIsGroup, voucherAccountInactive,
voucherDateOutsideFY, voucherFYLocked, voucherMissingParty,
voucherMissingNarration, accountNameBlank, accountCodeDuplicate,
accountGroupRequired, accountOpeningBalanceRequired,
financialYearOverlap, financialYearGapNotAllowed, financialYearZeroLength,
reportFinancialYearMissing, reportFinancialYearCompanyMismatch,
reportAsOfBeforeFinancialYear, reportAsOfAfterFinancialYear,
companyNameBlank, companyGstinInvalid, companyPanInvalid,
payrollNetMismatch, payrollEmployeeTerminated,
stockMovementQuantityZero, stockMovementCostMismatch, quantityExceedsStock,
arithmeticOverflow, internal
```

## 4. Database boundary names

```text
SQLiteDatabase
SQLValue
Row
DatabaseManager
CompanyHandle
SchemaVersion
Migration
MigrationRunner
SeedLoader
CompanyKeyStoring
CompanyKeyStore
RecoveryKeyCodec
RecoveryKeyError
LegacyKeyMigrationService
BackupService
RestoreService
```

`SQLiteError` lives in `Core/Validation/AppError.swift`; it is not declared by `SQLiteDatabase.swift`.

Migration types are frozen as `MigrationV001` through `MigrationV030`. The next persistent change uses `MigrationV031`; an existing migration is never renumbered, edited to mean something else, or removed from `MigrationRunner.defaultMigrations`.

## 5. Repository names

```text
RegistryRepository
CompanyRepository
FinancialYearRepository
FinancialYearOpeningBalanceRepository
AccountGroupRepository
AccountRepository
VoucherRepository
VoucherSequenceRepository
VoucherDraftRepository
VoucherTemplateRepository
VoucherItemLineRepository
LedgerLineRepository
AccountingWorkflowsRepository
InventoryRepository
InventoryOrderRepository
BOMRepository
PartyProfileRepository
PayrollRepository
BankReconciliationRepository
AuditRepository
ReportRepository
MasterDataRepository
```

The following v24 identifiers are frozen:

```text
PartyUsage
PartyProfile
avelo_party_profiles
account_id
company_id
usage
credit_limit_paise
default_credit_period_days
maintain_billwise
created_at
updated_at
idx_avelo_party_profiles_company_usage
trg_avelo_party_profiles_company_insert
trg_avelo_party_profiles_company_update
```

The following v26 identifiers are frozen:

```text
CompanyFeatureSet
WorkspaceIdentifier
WorkspaceConfiguration
avelo_workspace_configurations
id
company_id
workspace_id
format_version
payload_json
created_at
updated_at
idx_avelo_workspace_configurations_company
```

Repository method names are not globally frozen by this file. Public renames still require call-site and test updates, but persistence compatibility is governed by SQL identifiers below.

## 6. Service names

```text
CompanyService
FinancialYearService
AccountService
VoucherService
VoucherTemplateService
ItemInvoiceService
InventoryService
InventoryOrderService
BOMService
PayrollService
GSTService
GSTInvoiceCalculator
InvoicePDFService
BankReconciliationService
AuditService
ReportService
ValidationService
MasterDataService
```

There is no `TransactionService`. Double-entry posting belongs to `VoucherService` and the explicit item-invoice transaction belongs to `ItemInvoiceService`.

## 7. Validation and report namespaces

```text
AppError
SQLiteError
ValidationError
ValidationErrorCode
ValidationResult
CompanyInputValidator
FinancialYearInputValidator
AccountInputValidator
VoucherDraftValidator
PayrollDraftValidator
StockMovementValidator
ReportResult
ReportService
ReconciliationCheck
```

Validators are concrete value types. There is no frozen `Validator` protocol.

All report DTOs remain nested under `ReportResult`. Adding a DTO is allowed; moving one to a new top-level namespace is a compatibility rename.

## 8. SQL database and table names

Registry database filename:

```text
avelo_registry.sqlite
```

Registry table:

```text
avelo_registry_companies
```

Company tables through schema v27:

```text
avelo_companies
avelo_financial_years
avelo_financial_year_opening_balances
avelo_account_groups
avelo_accounts
avelo_voucher_types
avelo_vouchers
avelo_ledger_lines
avelo_voucher_sequences
avelo_voucher_templates
avelo_voucher_drafts
avelo_voucher_item_lines
avelo_bill_allocations
avelo_cheques
avelo_inventory_items
avelo_inventory_locations
avelo_inventory_orders
avelo_inventory_order_lines
avelo_inventory_reorder_levels
avelo_boms
avelo_bom_components
avelo_stock_movements
avelo_payroll_employees
avelo_payroll_entries
avelo_bank_reconciliations
avelo_bank_statement_lines
avelo_audit_events
avelo_migrations
trn_accounting
trn_inventory
trn_inventory_cost_allocations
```

`Avelo_Schema.md` gives the readable column contract. Executable migrations remain authoritative for exact DDL. Any new company-scoped table must also update restore/remap coverage; `avelo_voucher_item_lines` currently exposes the missing-remap blocker `AVL-P0-036`.

## 9. Keyboard identifiers

`KeyboardShortcutID` values:

```text
kNew, kSave, kCancel, kDelete, kDuplicate,
kFocusParty, kFocusNarration, kAddLine, kDuplicateLine,
kSearch, kCommandPalette, kSwitchCompany, kSwitchFY,
kBackup, kRestore, kToggleSidebar, kPostInventoryLink
```

These identifiers are stable action names, not proof that their current key chords are correct. PRD §8.1 owns the user contract; shortcut mismatches are tracked by `AVL-P0-020` and `AVL-P1-044`.

## 10. File and type names that must not appear in shipped code

- `NetworkService`, `APIClient`, or URL-session wrappers: violates offline rule.
- `MoneyDouble`, `AmountDouble`, or another floating money type: violates exact arithmetic.
- `GlobalState` or singleton `AppState`: violates context ownership.
- a production `MockDatabase`, `FakeService`, or `StubRepository`: tests use isolated real SQLite fixtures; test-only fakes stay under `Tests/`.
- a new `*Manager` unless the type genuinely owns lifecycle/resources and the architecture document is updated. `DatabaseManager` is the existing approved manager.

## 11. Freeze review checklist

Before accepting a naming change:

1. Identify whether the name is Swift-only, persisted, serialized, user-visible, or used by seed/report logic.
2. Provide migration/backfill and restore compatibility for persisted changes.
3. Update schema, PRD/architecture, tests, seed resources, exports, and audit snapshots that carry the name.
4. Prove fresh-create and every supported upgrade converge.
5. Record the change and its compatibility window on the release board.
