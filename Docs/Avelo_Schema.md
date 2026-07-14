# Avelo Schema

This is the human-readable persistence contract for the current converged company schema. Executable authority is `SchemaVersion.current`, `MigrationRunner.defaultMigrations`, and `MigrationV###`; this document must be updated in the same change. If prose and executable DDL differ, release is blocked until they converge.

Current executable schema: **v22**.

## Conventions

- All table names are prefixed `avelo_`.
- All column names are `snake_case`.
- UUIDs: `TEXT` in canonical 36-character form, generated and strictly decoded in Swift.
- Dates (calendar dates with no time): `TEXT` in `yyyy-MM-dd`.
- Timestamps (events with time): `TEXT` in `yyyy-MM-ddTHH:mm:ss.SSSZ` (UTC ISO 8601).
- Money: `INTEGER` storing **paise** (Int64 in Swift). Never `REAL`.
- Booleans: `INTEGER` 0/1 with `CHECK(col IN (0,1))`.
- Most entity tables have `id TEXT PRIMARY KEY`; snapshot/join tables may use a composite primary key, and `avelo_migrations` uses an integer version key.
- Foreign-key delete behavior is table-specific. Durable financial history normally uses `RESTRICT`; scratch or dependent rows may use `CASCADE` only where the migration explicitly defines it.
- All `TEXT` columns that must be non-empty have `CHECK(length(trim(col)) > 0)`.
- Timestamps are written explicitly by the app unless the executable DDL states otherwise.
- Legacy `REAL` BOM columns remain upgrade input only. Runtime BOM quantities use exact numerator/denominator columns introduced by v22.

## Foreign keys & pragmas

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

These are set in `SQLiteDatabase.open` for every connection.

## 1. avelo_companies

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| name | TEXT | NOT NULL, CHECK(length(trim(name)) > 0), UNIQUE |
| address_line1 | TEXT | nullable |
| address_line2 | TEXT | nullable |
| city | TEXT | nullable |
| state | TEXT | nullable |
| pincode | TEXT | nullable |
| country | TEXT | NOT NULL DEFAULT 'India' |
| gstin | TEXT | nullable, CHECK(length(gstin) = 15 OR gstin IS NULL) |
| pan | TEXT | nullable, CHECK(length(pan) = 10 OR pan IS NULL) |
| base_currency | TEXT | NOT NULL DEFAULT 'INR', CHECK(base_currency = 'INR') |
| is_inventory_enabled | INTEGER | NOT NULL DEFAULT 0, CHECK(is_inventory_enabled IN (0,1)) |
| inventory_link_mode | TEXT | NOT NULL DEFAULT 'manual', CHECK(inventory_link_mode IN ('manual','autoPrompt','autoSilent')) |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

Indexes: `idx_avelo_companies_name` on `(name)`.

## 2. avelo_financial_years

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| label | TEXT | NOT NULL, e.g. `2025-26` |
| start_date | TEXT | NOT NULL, `yyyy-MM-dd` |
| end_date | TEXT | NOT NULL, `yyyy-MM-dd` |
| books_begin_date | TEXT | NOT NULL |
| is_locked | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| is_closed | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_fy_company` on `(company_id)`
- `idx_avelo_fy_dates` on `(company_id, start_date, end_date)`
- UNIQUE `(company_id, label)`

Trigger:
```sql
CREATE TRIGGER trg_avelo_fy_no_overlap
BEFORE INSERT ON avelo_financial_years
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Financial year overlaps an existing year for this company')
  WHERE EXISTS (
    SELECT 1 FROM avelo_financial_years fy
    WHERE fy.company_id = NEW.company_id
      AND NOT (NEW.end_date < fy.start_date OR NEW.start_date > fy.end_date)
  );
END;
```

## 3. avelo_account_groups

Hierarchical. A group with `parent_group_id IS NULL` is a root. Groups aggregate for reports; ledgers (in `avelo_accounts`) hold balances.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| parent_group_id | TEXT | nullable, FK avelo_account_groups(id) |
| code | TEXT | NOT NULL, e.g. `CAPITAL` |
| name | TEXT | NOT NULL |
| nature | TEXT | NOT NULL, CHECK(nature IN ('assets','liabilities','income','expense')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| sort_order | INTEGER | NOT NULL DEFAULT 0 |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_groups_company` on `(company_id)`
- `idx_avelo_groups_parent` on `(parent_group_id)`
- UNIQUE `(company_id, code)`

## 4. avelo_accounts

Only ledgers (not groups) are inserted here. The presence of a row in this table means "this is a leaf account that can hold a balance and be posted to".

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| group_id | TEXT | NOT NULL, FK avelo_account_groups(id) |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| opening_balance_paise | INTEGER | NOT NULL DEFAULT 0 |
| opening_balance_side | TEXT | NOT NULL DEFAULT 'debit', CHECK(opening_balance_side IN ('debit','credit')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| is_bank_account | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| gstin | TEXT | nullable |
| mailing_name | TEXT | nullable |
| mailing_address | TEXT | nullable |
| state_code | TEXT | nullable; GST state code is validated at the service boundary |
| country | TEXT | nullable |
| gst_registration_type | TEXT | nullable; decoded strictly to `GSTRegistrationType` when present |
| maintain_billwise | INTEGER | NOT NULL DEFAULT 0, strict 0/1 decode |
| credit_period_days | INTEGER | nullable |
| last_used_at | TEXT | nullable |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_accounts_company` on `(company_id)`
- `idx_avelo_accounts_group` on `(group_id)`
- `idx_avelo_accounts_last_used` on `(company_id, last_used_at DESC)`
- UNIQUE `(company_id, code)`

Trigger:
```sql
CREATE TRIGGER trg_avelo_accounts_group_must_be_leaf
BEFORE INSERT ON avelo_accounts
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Account must be posted under a leaf group (a group with no child groups)')
  WHERE EXISTS (SELECT 1 FROM avelo_account_groups g WHERE g.parent_group_id = NEW.group_id);
END;
```

## 5. avelo_voucher_types

Seeded per company with the 10 codes in `VoucherType.Code`. User can add custom non-system types; system types (`is_system = 1`) are not editable.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| code | TEXT | NOT NULL, CHECK(code IN ('journal','sales','purchase','payment','receipt','contra','creditNote','debitNote','opening','payroll')) |
| name | TEXT | NOT NULL |
| abbreviation | TEXT | NOT NULL, e.g. `JV`, `SALES`, `PURCH` |
| is_system | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| affects_inventory | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| sort_order | INTEGER | NOT NULL DEFAULT 0 |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 6. avelo_vouchers

The header. The lines live in `avelo_ledger_lines`. There is no separate `transactions` table — the voucher IS the transaction. A voucher that reverses another carries `is_reversal = 1` and `reversal_of_id` pointing back.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| financial_year_id | TEXT | NOT NULL, FK avelo_financial_years(id) |
| voucher_type_code | TEXT | NOT NULL, FK by logical reference to avelo_voucher_types(code) |
| number | TEXT | NOT NULL, e.g. `S/2025-26/00012` |
| date | TEXT | NOT NULL, `yyyy-MM-dd` |
| party_account_id | TEXT | nullable, FK avelo_accounts(id) |
| narration | TEXT | NOT NULL DEFAULT '' |
| is_reversal | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| reversal_of_id | TEXT | nullable, FK avelo_vouchers(id) |
| status | TEXT | NOT NULL DEFAULT 'open', CHECK IN (`open`, `cancelled`) |
| cancelled_at | TEXT | nullable |
| cancelled_by | TEXT | nullable |
| cancellation_reason | TEXT | nullable |
| cancellation_voucher_id | TEXT | nullable, FK avelo_vouchers(id) |
| is_posted | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) (drafts are 0) |
| total_paise | INTEGER | NOT NULL, CHECK(total_paise > 0) |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_vouchers_company_date` on `(company_id, date)`
- `idx_avelo_vouchers_fy` on `(financial_year_id)`
- `idx_avelo_vouchers_type` on `(voucher_type_code, date)`
- `idx_avelo_vouchers_party` on `(party_account_id)`
- `idx_avelo_vouchers_reversal` on `(reversal_of_id)`
- `idx_avelo_vouchers_status` on `(status)`
- `idx_avelo_vouchers_cancel_link` on `(cancellation_voucher_id)`
- UNIQUE `(company_id, financial_year_id, voucher_type_code, number)`

Trigger: enforce date falls within the FY:
```sql
CREATE TRIGGER trg_avelo_voucher_date_in_fy
BEFORE INSERT ON avelo_vouchers
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Voucher date is outside its financial year')
  WHERE NOT EXISTS (
    SELECT 1 FROM avelo_financial_years fy
    WHERE fy.id = NEW.financial_year_id
      AND fy.company_id = NEW.company_id
      AND NEW.date BETWEEN fy.start_date AND fy.end_date
  );
END;
```

Trigger: reject write into a locked FY:
```sql
CREATE TRIGGER trg_avelo_voucher_fy_locked_insert
BEFORE INSERT ON avelo_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = NEW.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; new vouchers are not allowed');
END;

CREATE TRIGGER trg_avelo_voucher_fy_locked_update
BEFORE UPDATE ON avelo_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; voucher edits are not allowed');
END;

CREATE TRIGGER trg_avelo_voucher_fy_locked_delete
BEFORE DELETE ON avelo_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM avelo_financial_years WHERE id = OLD.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; voucher deletes are not allowed');
END;
```

(Same triggers apply to `avelo_ledger_lines` since lines inherit lock state from their voucher.)

## 7. avelo_ledger_lines

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| voucher_id | TEXT | NOT NULL, FK avelo_vouchers(id) |
| account_id | TEXT | NOT NULL, FK avelo_accounts(id) |
| amount_paise | INTEGER | NOT NULL, CHECK(amount_paise > 0) |
| side | TEXT | NOT NULL, CHECK(side IN ('debit','credit')) |
| tax_code | TEXT | nullable, HSN/SAC code for invoice line display (AVL-P0-022), e.g. `7208`, `9983` — not a GST-ledger-account discriminator; that role is played by `Account.code` values (`IGST_OUTPUT`, `CGST_OUTPUT`, `SGST_OUTPUT`, `CESS`) on separate GST-liability accounts, read via `GSTService.voucherTaxBreakdown`/`gstr1InvoiceRows` |
| cost_center | TEXT | nullable |
| line_order | INTEGER | NOT NULL |

Indexes:
- `idx_avelo_lines_voucher` on `(voucher_id, line_order)`
- `idx_avelo_lines_account` on `(account_id)`
- `idx_avelo_lines_company_side` on `(company_id, side)`

Trigger: lock inheritance from voucher.
```sql
CREATE TRIGGER trg_avelo_lines_fy_locked_insert
BEFORE INSERT ON avelo_ledger_lines
FOR EACH ROW
WHEN (SELECT v.financial_year_id FROM avelo_vouchers v WHERE v.id = NEW.voucher_id) IN
     (SELECT id FROM avelo_financial_years WHERE is_locked = 1)
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked');
END;
-- (mirror for UPDATE and DELETE)
```

## 8. avelo_inventory_items

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| unit | TEXT | NOT NULL, e.g. `KG`, `MT`, `PCS`, `L`, `M` |
| alternate_unit | TEXT | nullable |
| alt_unit_base_numerator | INTEGER | nullable; paired with denominator and > 0 when present |
| alt_unit_base_denominator | INTEGER | nullable; paired with numerator and > 0 when present |
| valuation_method | TEXT | NOT NULL DEFAULT 'fifo', CHECK(valuation_method IN ('fifo','weightedAverage')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| hsn_code | TEXT | nullable |
| gst_rate_bps | INTEGER | nullable; full GST rate in basis points |
| gst_cess_rate_bps | INTEGER | nullable |
| gst_taxability | TEXT | NOT NULL DEFAULT 'taxable', CHECK IN (`taxable`, `exempt`, `nilRated`) |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 9. avelo_inventory_orders

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| order_type | TEXT | NOT NULL, CHECK(order_type IN ('purchaseOrder','salesOrder')) |
| number | TEXT | NOT NULL |
| party_account_id | TEXT | NOT NULL, FK avelo_accounts(id) |
| order_date | TEXT | NOT NULL, `yyyy-MM-dd` |
| expected_date | TEXT | nullable |
| status | TEXT | NOT NULL DEFAULT 'open', CHECK(status IN ('open','closed','cancelled')) |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

UNIQUE `(company_id, order_type, number)`.

## 10. avelo_inventory_order_lines

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| order_id | TEXT | NOT NULL, FK avelo_inventory_orders(id) ON DELETE RESTRICT |
| item_id | TEXT | NOT NULL, FK avelo_inventory_items(id) |
| quantity | INTEGER | NOT NULL, CHECK(quantity > 0) |
| fulfilled_quantity | INTEGER | NOT NULL DEFAULT 0, CHECK(fulfilled_quantity >= 0 AND fulfilled_quantity <= quantity) |
| unit_rate_paise | INTEGER | NOT NULL DEFAULT 0, CHECK(unit_rate_paise >= 0) |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_inventory_order_lines_order` on `(order_id)`
- `idx_avelo_inventory_order_lines_item` on `(company_id, item_id)`

## 11. avelo_inventory_reorder_levels

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK avelo_companies(id) |
| item_id | TEXT | NOT NULL, FK avelo_inventory_items(id) |
| minimum_quantity | INTEGER | NOT NULL, CHECK(minimum_quantity >= 0) |
| reorder_quantity | INTEGER | NOT NULL, CHECK(reorder_quantity >= 0) |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

UNIQUE `(company_id, item_id)`.

## 12. avelo_stock_movements

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| item_id | TEXT | NOT NULL, FK avelo_inventory_items(id) |
| voucher_id | TEXT | nullable, FK avelo_vouchers(id) |
| date | TEXT | NOT NULL, `yyyy-MM-dd` |
| movement_type | TEXT | NOT NULL, CHECK(movement_type IN ('in','out','adjustment')) |
| quantity | INTEGER | NOT NULL, CHECK(quantity > 0) — for `out` type, balance must remain ≥ 0 (enforced in service) |
| unit_cost_paise | INTEGER | NOT NULL, CHECK(unit_cost_paise >= 0) |
| total_value_paise | INTEGER | NOT NULL, CHECK(total_value_paise >= 0) |
| reference_voucher_number | TEXT | nullable |
| reason | TEXT | nullable |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_mov_item_date` on `(item_id, date)`
- `idx_avelo_mov_company_date` on `(company_id, date)`
- `idx_avelo_mov_voucher` on `(voucher_id)`

## 13. avelo_payroll_employees

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| designation | TEXT | nullable |
| pan | TEXT | nullable, CHECK(length(pan) = 10 OR pan IS NULL) |
| bank_account_id | TEXT | nullable, FK avelo_accounts(id) |
| base_salary_paise | INTEGER | NOT NULL, CHECK(base_salary_paise >= 0) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| joined_on | TEXT | NOT NULL |
| end_date | TEXT | nullable |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 14. avelo_payroll_entries

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| employee_id | TEXT | NOT NULL, FK avelo_payroll_employees(id) |
| financial_year_id | TEXT | NOT NULL, FK avelo_financial_years(id) |
| voucher_id | TEXT | nullable, FK avelo_vouchers(id) |
| month | INTEGER | NOT NULL, CHECK(month BETWEEN 1 AND 12) |
| year | INTEGER | NOT NULL, CHECK(year BETWEEN 2000 AND 9999) |
| gross_paise | INTEGER | NOT NULL, CHECK(gross_paise > 0) |
| deductions_paise | INTEGER | NOT NULL DEFAULT 0, CHECK(deductions_paise >= 0) |
| net_paise | INTEGER | NOT NULL, CHECK(net_paise = gross_paise - deductions_paise) |
| posted_at | TEXT | NOT NULL |

Indexes:
- `idx_avelo_payroll_emp_period` on `(employee_id, year, month)`
- `idx_avelo_payroll_company_period` on `(company_id, year, month)`

## 15. avelo_audit_events

Append-only. Triggers reject UPDATE and DELETE.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| timestamp | TEXT | NOT NULL |
| actor | TEXT | NOT NULL DEFAULT 'user' |
| action | TEXT | NOT NULL, CHECK(action IN (allowed AuditAction values)) |
| entity_type | TEXT | NOT NULL, e.g. `voucher`, `account`, `company` |
| entity_id | TEXT | NOT NULL |
| snapshot_before_json | TEXT | nullable |
| snapshot_after_json | TEXT | nullable |
| reason | TEXT | nullable |
| sequence_number | INTEGER | NOT NULL, > 0 |
| previous_chain_hmac | TEXT | nullable for first event; otherwise 64 hex characters |
| chain_hmac | TEXT | NOT NULL, 64 hex characters |

Indexes:
- `idx_avelo_audit_entity` on `(company_id, entity_type, entity_id)`
- `idx_avelo_audit_time` on `(company_id, timestamp)`
- unique `idx_avelo_audit_sequence` on `(company_id, sequence_number)`

Triggers:
```sql
CREATE TRIGGER trg_avelo_audit_no_update
BEFORE UPDATE ON avelo_audit_events
BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;

CREATE TRIGGER trg_avelo_audit_no_delete
BEFORE DELETE ON avelo_audit_events
BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
```

## 16. avelo_voucher_sequences

Per (company, FY, type) counter. Updated atomically when a voucher is posted.

| Column | Type | Constraint |
|---|---|---|
| company_id | TEXT | NOT NULL |
| financial_year_id | TEXT | NOT NULL |
| voucher_type_code | TEXT | NOT NULL |
| last_number | INTEGER | NOT NULL DEFAULT 0 |
| prefix | TEXT | nullable, e.g. `S` for sales |
| suffix | TEXT | nullable |
| padding | INTEGER | NOT NULL DEFAULT 5 |

PRIMARY KEY `(company_id, financial_year_id, voucher_type_code)`.

## 17. avelo_voucher_templates

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| name | TEXT | NOT NULL |
| voucher_type_code | TEXT | NOT NULL |
| description | TEXT | nullable |
| template_lines_json | TEXT | NOT NULL — JSON array of `{accountId, side, amountPaise, taxCode?}` |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, name)`.

## 18. avelo_bank_reconciliations

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| bank_account_id | TEXT | NOT NULL, FK avelo_accounts(id) |
| voucher_id | TEXT | NOT NULL, FK avelo_vouchers(id) |
| statement_date | TEXT | NOT NULL |
| statement_amount_paise | INTEGER | NOT NULL |
| is_cleared | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| cleared_at | TEXT | nullable |
| note | TEXT | nullable |
| created_at | TEXT | NOT NULL |

UNIQUE `(voucher_id)` — one reconciliation row per voucher.
Index `idx_avelo_br_account_cleared` on `(bank_account_id, is_cleared)`.

## 19. avelo_bank_statement_lines

Raw imported bank statement lines were introduced in v4 so unmatched lines persist until later reconciliation. They remain part of the current schema and are protected by company-ownership and fiscal-lock policy.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| bank_account_id | TEXT | NOT NULL, FK avelo_accounts(id) |
| statement_date | TEXT | NOT NULL |
| amount_paise | INTEGER | NOT NULL |
| narration | TEXT | NOT NULL |
| import_batch_id | TEXT | nullable |
| imported_at | TEXT | NOT NULL |
| matched_voucher_id | TEXT | nullable, FK avelo_vouchers(id) |
| is_cleared | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| cleared_at | TEXT | nullable |

Indexes:
- `idx_avelo_bank_statement_lines_account_date` on `(bank_account_id, statement_date)`.
- `idx_avelo_bank_statement_lines_clearance` on `(company_id, is_cleared, statement_date)`.
- `idx_avelo_bank_statement_lines_matched_voucher` on `(matched_voucher_id)`.

## 20. avelo_voucher_drafts

Autosaved, in-progress "new voucher" entries (AVL-P0-018), added in V18. Deliberately outside the double-entry/audit model: a row here is never validated, never balanced, and never posted automatically. It exists only so a crash or quit does not silently discard everything the user typed, and is deleted the moment the user explicitly posts or cancels. Recovery only ever offers the most-recently-updated row for a company and never auto-posts it.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK `avelo_companies(id)` ON DELETE CASCADE |
| voucher_type_code | TEXT | NOT NULL |
| date | TEXT | NOT NULL |
| party_account_id | TEXT | nullable, no FK (scratch value only, re-validated on resume) |
| account_ledger_id | TEXT | nullable, no FK; cash/bank ledger for recovered single-entry mode, re-validated on resume |
| narration | TEXT | NOT NULL DEFAULT '' |
| bill_reference_type | TEXT | nullable |
| bill_reference_number | TEXT | nullable |
| cheque_number | TEXT | nullable |
| cheque_due_date | TEXT | nullable |
| lines_json | TEXT | NOT NULL — JSON array of `{accountId, amount, side, taxCode?, costCenter?}` |
| updated_at | TEXT | NOT NULL |

Index: `idx_avelo_voucher_drafts_company` on `(company_id, updated_at)`.

## 21. avelo_financial_year_opening_balances

The carried opening snapshot published by FY close. It deliberately has no independent `id`; one account has at most one carried opening in a target FY.

| Column | Type | Constraint |
|---|---|---|
| financial_year_id | TEXT | NOT NULL, FK FY ON DELETE CASCADE |
| source_financial_year_id | TEXT | NOT NULL, FK FY ON DELETE CASCADE |
| account_id | TEXT | NOT NULL, FK account ON DELETE CASCADE |
| opening_balance_paise | INTEGER | NOT NULL |
| opening_balance_side | TEXT | NOT NULL, CHECK IN (`debit`, `credit`) |
| created_at | TEXT | NOT NULL |

Primary key: `(financial_year_id, account_id)`. Index: `idx_avelo_fy_opening_balances_source`.

## 22. avelo_bill_allocations

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK company RESTRICT |
| voucher_id | TEXT | NOT NULL, FK voucher RESTRICT |
| party_account_id | TEXT | NOT NULL, FK account RESTRICT |
| kind | TEXT | NOT NULL, CHECK IN (`New Ref`, `Agst Ref`, `Advance`, `On Account`) |
| reference_number | TEXT | nullable |
| allocated_paise | INTEGER | NOT NULL, > 0 |
| created_at | TEXT | NOT NULL |

Ownership triggers require voucher and party to belong to `company_id`. Indexes cover voucher, party/reference, and party/kind lookup.

## 23. avelo_cheques

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK company RESTRICT |
| voucher_id | TEXT | NOT NULL UNIQUE, FK voucher RESTRICT |
| cheque_number | TEXT | NOT NULL |
| issue_date | TEXT | NOT NULL |
| due_date | TEXT | nullable |
| status | TEXT | NOT NULL, CHECK IN (`issued`, `deposited`, `cleared`, `bounced`, `cancelled`) |
| bounced_reversal_voucher_id | TEXT | nullable, FK voucher RESTRICT |
| represented_from_cheque_id | TEXT | nullable, self-FK RESTRICT |
| created_at | TEXT | NOT NULL |

Ownership triggers protect voucher, reversal, and re-presentation references. Indexes cover company/status/number and represented-from lineage.

## 24. avelo_boms

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK company RESTRICT |
| assembly_item_id | TEXT | NOT NULL UNIQUE, FK inventory item RESTRICT |
| output_quantity | REAL | legacy v17 value retained for upgrade compatibility; not authoritative at runtime |
| output_quantity_numerator | INTEGER | NOT NULL DEFAULT 1, > 0; authoritative v22 value |
| output_quantity_denominator | INTEGER | NOT NULL DEFAULT 1, > 0; authoritative v22 value |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

The assembly item must belong to the same company. `idx_avelo_boms_company_assembly` supports company lookup.

## 25. avelo_bom_components

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK company RESTRICT |
| bom_id | TEXT | NOT NULL, FK BOM ON DELETE CASCADE |
| component_item_id | TEXT | NOT NULL, FK inventory item RESTRICT |
| quantity | REAL | legacy v17 value retained for upgrade compatibility; not authoritative at runtime |
| quantity_numerator | INTEGER | NOT NULL DEFAULT 1, > 0; authoritative v22 value |
| quantity_denominator | INTEGER | NOT NULL DEFAULT 1, > 0; authoritative v22 value |
| line_order | INTEGER | NOT NULL DEFAULT 0 |

`idx_avelo_bom_components_unique_item` enforces one component item per BOM after v22 coalesces legacy duplicates. Company and order indexes support guarded reads.

## 26. avelo_voucher_item_lines

Structured item-invoice evidence introduced by v20. These rows supplement, not replace, the balanced ledger lines.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK company RESTRICT |
| voucher_id | TEXT | NOT NULL, FK voucher ON DELETE CASCADE |
| item_id | TEXT | NOT NULL, FK item RESTRICT |
| quantity | INTEGER | NOT NULL, > 0 |
| rate_paise | INTEGER | NOT NULL, >= 0 |
| taxable_value_paise | INTEGER | NOT NULL, >= 0 |
| hsn_code | TEXT | nullable |
| gst_rate_bps | INTEGER | nullable |
| cgst_paise | INTEGER | NOT NULL DEFAULT 0 |
| sgst_paise | INTEGER | NOT NULL DEFAULT 0 |
| igst_paise | INTEGER | NOT NULL DEFAULT 0 |
| cess_paise | INTEGER | NOT NULL DEFAULT 0 |
| line_order | INTEGER | NOT NULL DEFAULT 0 |
| created_at | TEXT | NOT NULL |

Ownership trigger requires voucher and item to match `company_id`. Indexes cover voucher order and company/item. Restore currently omits this table from company-ID remapping; `AVL-P0-036` blocks release until that is fixed and proved.

### GST state-code lookup (not a database table)

Place of supply (AVL-P0-022) is derived from a GSTIN's leading two-digit state-code prefix (e.g. `27` = Maharashtra) rather than a separate address/state field on `Account`. The standard CBIC state-code table lives in `Avelo/Core/Validation/GSTStateCode.swift` as static Swift data, since the code list is fixed by statute and never changes at runtime.

## 27. avelo_migrations

| Column | Type | Constraint |
|---|---|---|
| version | INTEGER | PK |
| applied_at | TEXT | NOT NULL |
| description | TEXT | NOT NULL |

## 28. Registry DB tables (`avelo_registry.sqlite`)

### avelo_registry_companies

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| name | TEXT | NOT NULL |
| sqlite_file_name | TEXT | NOT NULL, e.g. `<uuid>.sqlite` |
| last_opened_at | TEXT | nullable |
| created_at | TEXT | NOT NULL |

## 29. Index summary (non-exhaustive human aid)

```
idx_avelo_companies_name
idx_avelo_fy_company
idx_avelo_fy_dates
idx_avelo_groups_company
idx_avelo_groups_parent
idx_avelo_accounts_company
idx_avelo_accounts_group
idx_avelo_accounts_last_used
idx_avelo_fy_opening_balances_source
idx_avelo_vouchers_company_date
idx_avelo_vouchers_fy
idx_avelo_vouchers_type
idx_avelo_vouchers_party
idx_avelo_vouchers_reversal
idx_avelo_vouchers_status
idx_avelo_vouchers_cancel_link
idx_avelo_lines_voucher
idx_avelo_lines_account
idx_avelo_lines_company_side
idx_avelo_inventory_orders_company_status
idx_avelo_inventory_order_lines_order
idx_avelo_inventory_order_lines_item
idx_avelo_inventory_reorder_company_item
idx_avelo_mov_item_date
idx_avelo_mov_company_date
idx_avelo_mov_voucher
idx_avelo_payroll_emp_period
idx_avelo_payroll_company_period
idx_avelo_audit_entity
idx_avelo_audit_time
idx_avelo_br_account_cleared
idx_avelo_bank_statement_lines_account_date
idx_avelo_bank_statement_lines_clearance
idx_avelo_bank_statement_lines_matched_voucher
idx_avelo_voucher_drafts_company
idx_avelo_bill_allocations_voucher
idx_avelo_bill_allocations_party_ref
idx_avelo_bill_allocations_party_kind
idx_avelo_cheques_company_status
idx_avelo_cheques_represented_from
idx_avelo_boms_company_assembly
idx_avelo_bom_components_bom_order
idx_avelo_bom_components_company_component
idx_avelo_bom_components_unique_item
idx_avelo_voucher_item_lines_voucher
idx_avelo_voucher_item_lines_company_item
idx_avelo_audit_sequence
idx_avelo_registry_name
```

## 30. Migration policy

- `SchemaVersion.current = 22` and `MigrationRunner.defaultMigrations` contains `MigrationV001` through `MigrationV022` in order.
- `MigrationRunner` reads `PRAGMA user_version` and `avelo_migrations`, then applies each pending migration in its own `SQLiteDatabase.write` transaction.
- Each migration is a `struct: Migration` with a numeric version, description, and `up(_ db: SQLiteDatabase) throws` body.
- Migrations are append-only. Never edit a past migration.
- Fresh databases begin at v1 and converge through the same ordered migrations as upgraded databases. Fresh-create and representative historical fixtures must have identical v22 tables, columns, indexes, triggers, strict-decoding behavior, and restore coverage.
- Every persistent change updates this document, schema-drift tests, restore/remap tables, backup/manifest compatibility, ownership and fiscal-lock triggers, and audit coverage as applicable.
- Unknown future versions, unreadable schema versions, wrong keys, and migration/backfill failures stop before publishing a replacement database.
