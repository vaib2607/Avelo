# Avelo Deferrals

## Phase 1 Checkpoint: Freeze Contract

Command:

```sh
swift test --filter SchemaDriftTests
```

Result: expected failure before schema alignment.

Confirmed drift against `Docs/Avelo_Schema.md` and `Docs/Avelo_Naming_Freeze.md`:

- Non-frozen company DB tables are present: `avelo_bank_statement_lines`, `avelo_bill_allocations`, `avelo_bom_components`, `avelo_boms`, `avelo_budgets`, `avelo_cheques`, `avelo_cost_categories`, `avelo_cost_centres`, `avelo_tcs_records`, `avelo_tds_records`.
- `avelo_inventory_items` contains non-frozen stock-master columns beyond `id`, `company_id`, `code`, `name`, `unit`, `valuation_method`, `is_active`, `created_at`.
- `avelo_stock_movements` contains non-frozen batch columns and expanded movement types beyond `in`, `out`, `adjustment`.
- `avelo_payroll_employees` and `avelo_payroll_entries` contain non-frozen salary-component/day-detail columns.
- `avelo_audit_events.action` permits non-frozen actions: `inventoryModeChanged`, `fyUnlocked`, `inventoryEnabled`, `itemCreated`, `itemUpdated`, `itemArchived`, `itemAccountLinked`, `stockMoved`, `employeeCreated`, `employeeUpdated`, `employeeDeactivated`, `payrollEntryPosted`, `bankStatementImported`, `bankStatementLineCleared`, `bankReconciled`.

## Deferred Non-Frozen Feature Slices

These slices are implemented in the current codebase but are outside the frozen schema contract and must be removed or kept unreachable until the freeze is updated in a future, explicit schema version:

- Cost centres, cost categories, budgets.
- Bill allocations, cheque records, TDS records, TCS records.
- Bank statement import lines separate from frozen `avelo_bank_reconciliations`.
- BOM tables and advanced stock-master fields.
- Batch/manufacture/expiry inventory tracking.
- Expanded inventory movement type taxonomy beyond `in`, `out`, `adjustment`.
- Payroll salary-component/day-detail persistence beyond the frozen payroll employee/entry columns.

## Phase Checkpoints

### Phase 2 Checkpoint: Schema Alignment

Commands:

```sh
swift test --filter SchemaDriftTests
swift test
```

Result: green after aligning `schema_v1.sql`, `MigrationV001`, active models, repositories, and services to the frozen schema. Deferred/non-frozen tables and columns are unreachable from active persistence paths.

### Phase 3 Checkpoint: Money/Quantity

Commands:

```sh
swift test --filter InventoryServiceTests
swift test --filter SchemaDriftTests/testFrozenInventoryAndPayrollColumnsMatchMigration
swift test
```

Result: green. Persisted stock quantities use integer storage; financial amounts remain paise integers. `Double` remains only in non-persisted display/report compatibility DTOs and deferred BOM models.

### Phase 4 Checkpoint: Financial Write

Commands:

```sh
swift test --filter Phase6HardeningTests
swift test --filter VoucherServiceTests
swift test --filter InventoryServiceTests
swift test
```

Result: green. Inventory operations enforce `is_inventory_enabled`, stock-out validation is atomic and returns `AppError.validation`, voucher posting returns auto-prompt inventory prompts, payroll posting writes the payroll voucher and entry in one transaction, and audit actions are normalized to frozen names.

### Phase 5 Checkpoint: Reports

Commands:

```sh
swift test --filter ReportBehaviorTests
swift test --filter AccountantRCFlowTests
swift test
```

Result: green. Day Book totals come from ledger lines, GST summary excludes opening balances, stock valuation uses grouped SQL over frozen movement types, and report cache invalidates when voucher edits change `updated_at`.

### Phase 6 Checkpoint: SQLite/Repositories

Commands:

```sh
swift test --filter SQLiteDatabaseTests
swift test --filter MalformedUUIDHandlingTests
swift test --filter RestoreServiceTests
swift test
```

Result: green. Row decoders throw on malformed required UUID/timestamp fields, optional integer reads stay integer-safe, nested repository writes were removed from active write paths, restore remaps only frozen company-scoped tables, and workflow repositories fail closed for deferred schema slices.

### Phase 7 Checkpoint: State/Errors

Commands:

```sh
swift test --filter AppEnvironmentFlowTests
swift test --filter VouchersViewModelTests
swift test --filter ReportsViewModelTests
swift test
```

Result: green. Account tree reloads are cancellable/stale-safe, close-company clears visible context/router state, user-facing errors are routed through typed `AppError` banners where actionable, and placeholder payroll component fields were removed from active UI and persistence.

### Final Verification Checkpoint

Commands:

```sh
rg -n "avelo_bill_allocations|avelo_cheques|avelo_tds_records|avelo_tcs_records|avelo_boms|avelo_bom_components|avelo_bank_statement_lines|avelo_cost_centres|avelo_cost_categories|avelo_budgets|alternate_unit|opening_quantity|gst_rate|stock_group|stock_category|godown|reorder_level|price_level|barcode|hsn_sac|is_archived|linked_account_id|batch_number|manufacture_date|expiry_date|basic_paise|hra_paise|other_allowances_paise|working_days|paid_days|overtime_paise|pf_applicable|esi_applicable|bankAccount:|ifsc:" Avelo Tests
swift test
```

Result: removed-schema reference scan returns no matches; full suite passes with 166 executed, 4 skipped, 0 failures.
