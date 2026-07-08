# Avelo Naming Freeze

Every type, method, table, and column name in Avelo is locked here. Later passes must use these exact names. Renaming requires updating this document first. Ad-hoc renames are rejected.

The pattern is `PascalCase` for types, `camelCase` for methods/properties, `snake_case` for SQL tables and columns, `UPPER_SNAKE_CASE` for enum cases in SQL.

---

## 1. App & environment

| Symbol | Kind | File |
|---|---|---|
| `AveloApp` | `struct` (App protocol) | `App/AveloApp.swift` |
| `AppEnvironment` | `@Observable @MainActor final class` | `App/AppEnvironment.swift` |
| `AppRouter` | `@Observable @MainActor final class` | `App/AppRouter.swift` |
| `SidebarDestination` | `enum` | `App/SidebarDestination.swift` |
| `WindowState` | `@Observable @MainActor final class` | `App/WindowState.swift` |
| `AppError` | `enum: Error` | `Core/Validation/AppError.swift` |
| `AppError.Code` | nested enum | same |

## 2. Core models (all in `Core/Models/`)

| Symbol | Kind | Notes |
|---|---|---|
| `Company` | `struct Codable Sendable` | id (UUID), name, address, gstin, pan, baseCurrency, createdAt, isInventoryEnabled, inventoryLinkMode |
| `Company.ID` | `typealias = UUID` | |
| `FinancialYear` | `struct` | id, companyId, label, startDate, endDate, isLocked, booksBeginDate, createdAt |
| `FinancialYear.ID` | `typealias = UUID` | |
| `AccountGroup` | `struct` | id, companyId, code, name, parentGroupId?, nature (enum), isActive |
| `AccountGroup.ID` | `typealias = UUID` | |
| `AccountNature` | `enum String` | case assets, liabilities, income, expense; has `normalBalance: EntrySide` |
| `Account` | `struct` | id, companyId, groupId, code, name, openingBalancePaise, openingBalanceSide, isActive, isBankAccount, gstin?, lastUsedAt?, createdAt |
| `Account.ID` | `typealias = UUID` | |
| `OpeningBalanceSide` | `enum String` | case debit, credit |
| `VoucherType` | `struct` | id, companyId, code, name, abbreviation, isSystem, affectsInventory, sortOrder |
| `VoucherType.Code` | `enum String` | case journal, sales, purchase, payment, receipt, contra, creditNote, debitNote, opening, payroll |
| `Voucher` | `struct` | id, companyId, financialYearId, typeCode, number, date, partyAccountId?, narration, isReversal, reversalOfId?, createdAt, updatedAt |
| `Voucher.ID` | `typealias = UUID` | |
| `LedgerLine` | `struct` | id, voucherId, accountId, amountPaise (Int64, always > 0), side (EntrySide), taxCode? (HSN/SAC code for invoice display, e.g. `7208`; not a GST-ledger discriminator — that's `Account.code`, e.g. `IGST_OUTPUT`), costCenter?, lineOrder |
| `LedgerLine.ID` | `typealias = UUID` | |
| `EntrySide` | `enum String` | case debit, credit |
| `Transaction` | alias for `Voucher` | The transaction is the voucher. No separate `Transaction` type. |
| `InventoryItem` | `struct` | id, companyId, code, name, unit, valuationMethod, isActive, createdAt |
| `InventoryItem.ID` | `typealias = UUID` | |
| `ValuationMethod` | `enum String` | case fifo, weightedAverage |
| `StockMovement` | `struct` | id, companyId, itemId, voucherId?, date, movementType, quantity, unitCostPaise, totalValuePaise, referenceVoucherNumber?, createdAt |
| `StockMovement.ID` | `typealias = UUID` | |
| `MovementType` | `enum String` | case stockIn, stockOut, adjustment |
| `PayrollEmployee` | `struct` | id, companyId, code, name, designation?, pan?, bankAccountId?, baseSalaryPaise, isActive, joinedOn, endDate? |
| `PayrollEmployee.ID` | `typealias = UUID` | |
| `PayrollEntry` | `struct` | id, companyId, employeeId, financialYearId, voucherId?, month, year, grossPaise, deductionsPaise, netPaise, postedAt |
| `PayrollEntry.ID` | `typealias = UUID` | |
| `AuditEvent` | `struct` | id, companyId, timestamp, actor, action (AuditAction), entityType, entityId, snapshotBeforeJson?, snapshotAfterJson?, reason? |
| `AuditEvent.ID` | `typealias = UUID` | |
| `AuditAction` | `enum String` | see §10 |
| `CompanyRegistryEntry` | `struct` | id, name, lastOpenedAt, sqliteFileName, createdAt |
| `BackupManifest` | `struct Codable` | schemaVersion, companyName, exportedAt, checksumSHA256, originalFileName |
| `ReportResult` | namespace enum | contains nested DTOs in §7 |
| `AppColor` | `enum` | semantic colors |

## 3. Database layer (`Core/Database/`)

| Symbol | Kind | File |
|---|---|---|
| `SQLiteDatabase` | `final class @unchecked Sendable` | `SQLiteDatabase.swift` |
| `SQLValue` | `enum Sendable` | same |
| `Row` | `struct` | same |
| `SQLiteError` | `enum Error` | same |
| `DatabaseManager` | `final actor` | `DatabaseManager.swift` |
| `CompanyHandle` | `final class` | same — wraps a `SQLiteDatabase` and the company id |
| `MigrationRunner` | `struct` | `MigrationRunner.swift` |
| `Migration` | `protocol` | same |
| `MigrationV001` | `struct: Migration` | same |
| `SchemaVersion` | `enum Int` | `SchemaVersion.swift` |
| `SeedLoader` | `struct` | `SeedLoader.swift` |
| `BackupService` | `struct Sendable` | `BackupService.swift` |
| `RestoreService` | `struct Sendable` | `RestoreService.swift` |

## 4. Repositories (`Core/Repositories/`)

All repositories are `struct Sendable` with the form `func <verb>... throws -> <Result>`.

| Type | Key methods |
|---|---|
| `CompanyRepository` | `findById`, `list`, `insert`, `update`, `disable` |
| `FinancialYearRepository` | `findById`, `listForCompany`, `findActive`, `insert`, `lock`, `unlock` |
| `AccountRepository` | `findById`, `listForCompany`, `listLedgersForGroup`, `findByCode`, `insert`, `update`, `disable`, `markUsed` |
| `AccountGroupRepository` | `findById`, `listRootsForCompany`, `listChildren`, `insert`, `update` |
| `VoucherRepository` | `findById`, `listForCompany(filter:)`, `nextNumber(companyId:typeCode:fyId:)`, `insert`, `update`, `markReversed` |
| `LedgerLineRepository` | `findForVoucher`, `insertBatch`, `deleteForVoucher`, `aggregateForAccount(filter:)` |
| `InventoryRepository` | `findItemById`, `listItemsForCompany`, `insertItem`, `updateItem`, `disableItem`, `insertMovement`, `listMovements(itemId:filter:)`, `runningBalance(itemId:asOf:)` |
| `PayrollRepository` | `findEmployeeById`, `listEmployeesForCompany`, `insertEmployee`, `updateEmployee`, `terminateEmployee`, `insertEntry`, `listEntries(filter:)` |
| `AuditRepository` | `append`, `listForCompany(filter:)`, `countForEntity` |
| `ReportRepository` | `ledgerReport`, `trialBalance`, `profitAndLoss`, `balanceSheet`, `gstSummary`, `dayBook`, `outstandingReport` (all return DTOs) |
| `RegistryRepository` | `listCompanies`, `register`, `unregister`, `touchLastOpened` |

## 5. Services (`Core/Services/`)

All services are `final class Sendable` with init taking their repository dependencies. No singletons; injected through `AppEnvironment`.

| Type | Responsibility |
|---|---|
| `CompanyService` | create, list, switch active, set inventory mode |
| `FinancialYearService` | create, close, lock/unlock, set active |
| `AccountService` | CRUD with group hierarchy and opening balances |
| `VoucherService` | create draft, validate, post, edit, reverse, list, get |
| `TransactionService` | low-level double-entry writer around a `VoucherService` call |
| `ReportService` | calls `ReportRepository`, applies caching only of the (filter signature, rows) tuple for the current view (in-memory, not persisted) |
| `InventoryService` | CRUD, stock movement post, COGS computation (for auto-silent), valuation (FIFO/WA) |
| `PayrollService` | CRUD, salary voucher draft, post, list |
| `GSTService` | summarize CGST/SGST/IGST/cess for a period, broken out input vs output |
| `BankReconciliationService` | record bank book entry, mark cleared, partial match, unmatch |
| `AuditService` | `record(event:)` used by all services inside their DB transaction |
| `ValidationService` | composes `VoucherValidator`, `AccountValidator`, `FYValidator`, returns `ValidationResult` |

## 6. Validation (`Core/Validation/`)

| Symbol | Notes |
|---|---|
| `ValidationError` | `struct`: `code: ValidationErrorCode`, `field: String?`, `message: String`, `suggestedFix: String?` |
| `ValidationErrorCode` | `enum String` — see §10 |
| `ValidationResult` | `enum`: `.valid`, `.invalid([ValidationError])` |
| `Validator` | `protocol { func validate() -> ValidationResult }` |
| `VoucherDraftValidator` | `struct: Validator` |
| `AccountInputValidator` | `struct: Validator` |
| `FinancialYearInputValidator` | `struct: Validator` |
| `CompanyInputValidator` | `struct: Validator` |
| `PayrollDraftValidator` | `struct: Validator` |
| `StockMovementValidator` | `struct: Validator` |

## 7. Report DTOs (all inside `ReportResult` namespace)

```
ReportResult.LedgerRow
ReportResult.LedgerReport
ReportResult.TrialBalanceRow
ReportResult.TrialBalance
ReportResult.ProfitLossSection
ReportResult.ProfitLoss
ReportResult.BalanceSheetSection
ReportResult.BalanceSheet
ReportResult.GstBucket
ReportResult.GstSummary
ReportResult.DayBookRow
ReportResult.OutstandingRow
ReportResult.StockValuationRow
ReportResult.ReportFilter      // struct
ReportResult.Section           // enum: assets, liabilities, income, expense
```

## 8. Utilities (`Core/Utilities/`)

| Type | Purpose |
|---|---|
| `Currency` | paise ↔ rupees helpers, formatting, parsing user input |
| `IndianFinancialYear` | year(for: Date), start(ofFY:), end(ofFY:), booksBeginDate logic |
| `DateFormatters` | shared `DateFormatter` instances; ISO yyyy-MM-dd for storage; display formatters per Indian locale |
| `VoucherNumberGenerator` | produces next sequential number per `(companyId, voucherTypeCode, financialYearId)` |
| `FiscalLockChecker` | isLocked(companyId, fyId, date) -> Bool |

## 9. UI

### Sidebar destinations (the only valid cases on `SidebarDestination`)
```
.dashboard, .accounts, .vouchers, .reports, .inventory, .payroll, .banking, .audit, .settings
```

### ViewModel naming
`<Feature>ViewModel` (e.g. `VoucherEntryViewModel`, `TrialBalanceViewModel`). ViewModels in a feature that have multiple screens use the screen name: `VoucherListViewModel`, `VoucherEntryViewModel`.

### View naming
`<Screen>View` (e.g. `VoucherEntryView`, `TrialBalanceView`). Helper subviews: `<Screen><Part>View` (e.g. `VoucherEditorRowView`).

## 10. Enums — full case lists

### `AuditAction`
```
companyCreated, companyUpdated,
financialYearCreated, financialYearLocked, financialYearClosed,
accountCreated, accountUpdated, accountDisabled,
voucherPosted, voucherEdited, voucherReversed,
openingBalancePosted,
stockItemCreated, stockItemUpdated, stockItemDisabled,
stockMovementPosted, stockMovementReversed,
payrollEmployeeCreated, payrollEmployeeUpdated, payrollEmployeeTerminated,
salaryPosted,
backupExported, backupImported,
companySwitched, financialYearSwitched
```

### `ValidationErrorCode`
```
voucherDebitCreditMismatch,
voucherTooFewLines,
voucherZeroAmountLine,
voucherDuplicateAccount,
voucherAccountIsGroup,
voucherAccountInactive,
voucherDateOutsideFY,
voucherFYLocked,
voucherMissingParty,
voucherMissingNarration,
accountNameBlank,
accountCodeDuplicate,
accountGroupRequired,
accountOpeningBalanceRequired,
financialYearOverlap,
financialYearGapNotAllowed,
financialYearZeroLength,
companyNameBlank,
companyGstinInvalid,
companyPanInvalid,
payrollNetMismatch,
payrollEmployeeTerminated,
stockMovementQuantityZero,
stockMovementCostMismatch,
quantityExceedsStock
```

### `InventoryLinkMode`
```
manual, autoPrompt, autoSilent
```

### `EntrySide` (SQL: `debit`, `credit`)
### `MovementType` (SQL: `in`, `out`, `adjustment`)
### `ValuationMethod` (SQL: `fifo`, `weightedAverage`)
### `VoucherType.Code` (SQL: codes below in `voucher_types.code`)

## 11. SQL tables and columns

All SQL identifiers are `snake_case`. UUIDs are stored as `TEXT` (lowercase 36-char). Dates are `TEXT` in ISO `yyyy-MM-dd`. Timestamps are `TEXT` in `yyyy-MM-ddTHH:mm:ss.SSSZ`. Money is `INTEGER` (Int64 paise). Booleans are `INTEGER` 0/1 with `CHECK(... IN (0,1))`.

Tables (all under `avelo_` prefix to keep namespacing obvious if we ever attach another DB):
```
avelo_companies
avelo_financial_years
avelo_account_groups
avelo_accounts
avelo_voucher_types
avelo_vouchers
avelo_ledger_lines
avelo_inventory_items
avelo_inventory_orders
avelo_inventory_order_lines
avelo_inventory_reorder_levels
avelo_stock_movements
avelo_payroll_employees
avelo_payroll_entries
avelo_audit_events
avelo_voucher_sequences
avelo_voucher_templates
avelo_bank_reconciliations
avelo_migrations
```

Registry DB tables (`avelo_registry.sqlite`):
```
avelo_registry_companies
```

Full column list lives in `Avelo_Schema.md`. Do not deviate from those column names.

## 12. Keyboard shortcut identifiers (used by `KeyboardShortcutMap`)

```
kNew, kSave, kCancel, kDelete, kDuplicate,
kFocusParty, kFocusNarration, kAddLine, kDuplicateLine,
kSearch, kCommandPalette, kSwitchCompany, kSwitchFY,
kBackup, kRestore, kToggleSidebar, kPostInventoryLink
```

## 13. Files that must NOT exist

These names must never appear as file or type names. They are reserved for future phases or are explicitly forbidden:

- `NetworkService`, `APIClient`, `URLSession*` — R-1
- `Double`-suffixed money types (`MoneyDouble`, `AmountDecimal`) — R-4
- `GlobalState`, `AppState` singletons — services are injected
- `MockDatabase`, `FakeService`, `StubRepository` — no mocks in release; tests use a real temp SQLite
- `*Manager` outside `DatabaseManager` and `AppEnvironment`
