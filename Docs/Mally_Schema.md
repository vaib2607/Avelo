# Mally Schema

The frozen SQLite schema. Every table, column, type, constraint, and index is defined here. Migration scripts must produce a DB that matches this document exactly. Renames require updating this doc first.

## Conventions

- All table names are prefixed `mally_`.
- All column names are `snake_case`.
- UUIDs: `TEXT` (lowercase 36-char, RFC 4122). Default to `lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || ...)` via a SQLite expression or generated in Swift.
- Dates (calendar dates with no time): `TEXT` in `yyyy-MM-dd`.
- Timestamps (events with time): `TEXT` in `yyyy-MM-ddTHH:mm:ss.SSSZ` (UTC ISO 8601).
- Money: `INTEGER` storing **paise** (Int64 in Swift). Never `REAL`.
- Booleans: `INTEGER` 0/1 with `CHECK(col IN (0,1))`.
- Every table has a primary key `id TEXT NOT NULL PRIMARY KEY`.
- Foreign keys use `REFERENCES mally_xxx(id) ON DELETE RESTRICT` (we don't cascade financial data; we use R-10 reversal/disable instead).
- All `TEXT` columns that must be non-empty have `CHECK(length(trim(col)) > 0)`.
- All timestamps have default `strftime('%Y-%m-%dT%H:%M:%fZ','now')` written by the app, not by SQL.

## Foreign keys & pragmas

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

These are set in `SQLiteDatabase.open` for every connection.

## 1. mally_companies

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

Indexes: `idx_mally_companies_name` on `(name)`.

## 2. mally_financial_years

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| label | TEXT | NOT NULL, e.g. `2025-26` |
| start_date | TEXT | NOT NULL, `yyyy-MM-dd` |
| end_date | TEXT | NOT NULL, `yyyy-MM-dd` |
| books_begin_date | TEXT | NOT NULL |
| is_locked | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| is_closed | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_fy_company` on `(company_id)`
- `idx_mally_fy_dates` on `(company_id, start_date, end_date)`
- UNIQUE `(company_id, label)`

Trigger:
```sql
CREATE TRIGGER trg_mally_fy_no_overlap
BEFORE INSERT ON mally_financial_years
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Financial year overlaps an existing year for this company')
  WHERE EXISTS (
    SELECT 1 FROM mally_financial_years fy
    WHERE fy.company_id = NEW.company_id
      AND NOT (NEW.end_date < fy.start_date OR NEW.start_date > fy.end_date)
  );
END;
```

## 3. mally_account_groups

Hierarchical. A group with `parent_group_id IS NULL` is a root. Groups aggregate for reports; ledgers (in `mally_accounts`) hold balances.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| parent_group_id | TEXT | nullable, FK mally_account_groups(id) |
| code | TEXT | NOT NULL, e.g. `CAPITAL` |
| name | TEXT | NOT NULL |
| nature | TEXT | NOT NULL, CHECK(nature IN ('assets','liabilities','income','expense')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| sort_order | INTEGER | NOT NULL DEFAULT 0 |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_groups_company` on `(company_id)`
- `idx_mally_groups_parent` on `(parent_group_id)`
- UNIQUE `(company_id, code)`

## 4. mally_accounts

Only ledgers (not groups) are inserted here. The presence of a row in this table means "this is a leaf account that can hold a balance and be posted to".

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| group_id | TEXT | NOT NULL, FK mally_account_groups(id) |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| opening_balance_paise | INTEGER | NOT NULL DEFAULT 0 |
| opening_balance_side | TEXT | NOT NULL DEFAULT 'debit', CHECK(opening_balance_side IN ('debit','credit')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| is_bank_account | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| gstin | TEXT | nullable |
| last_used_at | TEXT | nullable |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_accounts_company` on `(company_id)`
- `idx_mally_accounts_group` on `(group_id)`
- `idx_mally_accounts_last_used` on `(company_id, last_used_at DESC)`
- UNIQUE `(company_id, code)`

Trigger:
```sql
CREATE TRIGGER trg_mally_accounts_group_must_be_leaf
BEFORE INSERT ON mally_accounts
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Account must be posted under a leaf group (a group with no child groups)')
  WHERE EXISTS (SELECT 1 FROM mally_account_groups g WHERE g.parent_group_id = NEW.group_id);
END;
```

## 5. mally_voucher_types

Seeded per company with the 10 codes in `VoucherType.Code`. User can add custom non-system types; system types (`is_system = 1`) are not editable.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| code | TEXT | NOT NULL, CHECK(code IN ('journal','sales','purchase','payment','receipt','contra','creditNote','debitNote','opening','payroll')) |
| name | TEXT | NOT NULL |
| abbreviation | TEXT | NOT NULL, e.g. `JV`, `SALES`, `PURCH` |
| is_system | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| affects_inventory | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| sort_order | INTEGER | NOT NULL DEFAULT 0 |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 6. mally_vouchers

The header. The lines live in `mally_ledger_lines`. There is no separate `transactions` table — the voucher IS the transaction. A voucher that reverses another carries `is_reversal = 1` and `reversal_of_id` pointing back.

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| financial_year_id | TEXT | NOT NULL, FK mally_financial_years(id) |
| voucher_type_code | TEXT | NOT NULL, FK by logical reference to mally_voucher_types(code) |
| number | TEXT | NOT NULL, e.g. `S/2025-26/00012` |
| date | TEXT | NOT NULL, `yyyy-MM-dd` |
| party_account_id | TEXT | nullable, FK mally_accounts(id) |
| narration | TEXT | NOT NULL DEFAULT '' |
| is_reversal | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| reversal_of_id | TEXT | nullable, FK mally_vouchers(id) |
| is_posted | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) (drafts are 0) |
| total_paise | INTEGER | NOT NULL, CHECK(total_paise > 0) |
| created_at | TEXT | NOT NULL |
| updated_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_vouchers_company_date` on `(company_id, date)`
- `idx_mally_vouchers_fy` on `(financial_year_id)`
- `idx_mally_vouchers_type` on `(voucher_type_code, date)`
- `idx_mally_vouchers_party` on `(party_account_id)`
- `idx_mally_vouchers_reversal` on `(reversal_of_id)`
- UNIQUE `(company_id, financial_year_id, voucher_type_code, number)`

Trigger: enforce date falls within the FY:
```sql
CREATE TRIGGER trg_mally_voucher_date_in_fy
BEFORE INSERT ON mally_vouchers
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'Voucher date is outside its financial year')
  WHERE NOT EXISTS (
    SELECT 1 FROM mally_financial_years fy
    WHERE fy.id = NEW.financial_year_id
      AND fy.company_id = NEW.company_id
      AND NEW.date BETWEEN fy.start_date AND fy.end_date
  );
END;
```

Trigger: reject write into a locked FY:
```sql
CREATE TRIGGER trg_mally_voucher_fy_locked_insert
BEFORE INSERT ON mally_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM mally_financial_years WHERE id = NEW.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; new vouchers are not allowed');
END;

CREATE TRIGGER trg_mally_voucher_fy_locked_update
BEFORE UPDATE ON mally_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM mally_financial_years WHERE id = OLD.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; voucher edits are not allowed');
END;

CREATE TRIGGER trg_mally_voucher_fy_locked_delete
BEFORE DELETE ON mally_vouchers
FOR EACH ROW
WHEN (SELECT is_locked FROM mally_financial_years WHERE id = OLD.financial_year_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked; voucher deletes are not allowed');
END;
```

(Same triggers apply to `mally_ledger_lines` since lines inherit lock state from their voucher.)

## 7. mally_ledger_lines

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK mally_companies(id) |
| voucher_id | TEXT | NOT NULL, FK mally_vouchers(id) |
| account_id | TEXT | NOT NULL, FK mally_accounts(id) |
| amount_paise | INTEGER | NOT NULL, CHECK(amount_paise > 0) |
| side | TEXT | NOT NULL, CHECK(side IN ('debit','credit')) |
| tax_code | TEXT | nullable, e.g. `CGST_IN_9`, `SGST_IN_9`, `IGST_IN_18`, `CESS_1` |
| cost_center | TEXT | nullable |
| line_order | INTEGER | NOT NULL |

Indexes:
- `idx_mally_lines_voucher` on `(voucher_id, line_order)`
- `idx_mally_lines_account` on `(account_id)`
- `idx_mally_lines_company_side` on `(company_id, side)`

Trigger: lock inheritance from voucher.
```sql
CREATE TRIGGER trg_mally_lines_fy_locked_insert
BEFORE INSERT ON mally_ledger_lines
FOR EACH ROW
WHEN (SELECT v.financial_year_id FROM mally_vouchers v WHERE v.id = NEW.voucher_id) IN
     (SELECT id FROM mally_financial_years WHERE is_locked = 1)
BEGIN
  SELECT RAISE(ABORT, 'Financial year is locked');
END;
-- (mirror for UPDATE and DELETE)
```

## 8. mally_inventory_items

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| unit | TEXT | NOT NULL, e.g. `KG`, `MT`, `PCS`, `L`, `M` |
| valuation_method | TEXT | NOT NULL DEFAULT 'fifo', CHECK(valuation_method IN ('fifo','weightedAverage')) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 9. mally_stock_movements

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| item_id | TEXT | NOT NULL, FK mally_inventory_items(id) |
| voucher_id | TEXT | nullable, FK mally_vouchers(id) |
| date | TEXT | NOT NULL, `yyyy-MM-dd` |
| movement_type | TEXT | NOT NULL, CHECK(movement_type IN ('in','out','adjustment')) |
| quantity | INTEGER | NOT NULL, CHECK(quantity > 0) — for `out` type, balance must remain ≥ 0 (enforced in service) |
| unit_cost_paise | INTEGER | NOT NULL, CHECK(unit_cost_paise >= 0) |
| total_value_paise | INTEGER | NOT NULL, CHECK(total_value_paise >= 0) |
| reference_voucher_number | TEXT | nullable |
| reason | TEXT | nullable |
| created_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_mov_item_date` on `(item_id, date)`
- `idx_mally_mov_company_date` on `(company_id, date)`
- `idx_mally_mov_voucher` on `(voucher_id)`

## 10. mally_payroll_employees

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| code | TEXT | NOT NULL |
| name | TEXT | NOT NULL |
| designation | TEXT | nullable |
| pan | TEXT | nullable, CHECK(length(pan) = 10 OR pan IS NULL) |
| bank_account_id | TEXT | nullable, FK mally_accounts(id) |
| base_salary_paise | INTEGER | NOT NULL, CHECK(base_salary_paise >= 0) |
| is_active | INTEGER | NOT NULL DEFAULT 1, CHECK IN (0,1) |
| joined_on | TEXT | NOT NULL |
| end_date | TEXT | nullable |
| created_at | TEXT | NOT NULL |

UNIQUE `(company_id, code)`.

## 11. mally_payroll_entries

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| employee_id | TEXT | NOT NULL, FK mally_payroll_employees(id) |
| financial_year_id | TEXT | NOT NULL, FK mally_financial_years(id) |
| voucher_id | TEXT | nullable, FK mally_vouchers(id) |
| month | INTEGER | NOT NULL, CHECK(month BETWEEN 1 AND 12) |
| year | INTEGER | NOT NULL, CHECK(year BETWEEN 2000 AND 9999) |
| gross_paise | INTEGER | NOT NULL, CHECK(gross_paise > 0) |
| deductions_paise | INTEGER | NOT NULL DEFAULT 0, CHECK(deductions_paise >= 0) |
| net_paise | INTEGER | NOT NULL, CHECK(net_paise = gross_paise - deductions_paise) |
| posted_at | TEXT | NOT NULL |

Indexes:
- `idx_mally_payroll_emp_period` on `(employee_id, year, month)`
- `idx_mally_payroll_company_period` on `(company_id, year, month)`

## 12. mally_audit_events

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

Indexes:
- `idx_mally_audit_entity` on `(company_id, entity_type, entity_id)`
- `idx_mally_audit_time` on `(company_id, timestamp)`

Triggers:
```sql
CREATE TRIGGER trg_mally_audit_no_update
BEFORE UPDATE ON mally_audit_events
BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;

CREATE TRIGGER trg_mally_audit_no_delete
BEFORE DELETE ON mally_audit_events
BEGIN SELECT RAISE(ABORT, 'Audit events are immutable'); END;
```

## 13. mally_voucher_sequences

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

## 14. mally_voucher_templates

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

## 15. mally_bank_reconciliations

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| company_id | TEXT | NOT NULL, FK |
| bank_account_id | TEXT | NOT NULL, FK mally_accounts(id) |
| voucher_id | TEXT | NOT NULL, FK mally_vouchers(id) |
| statement_date | TEXT | NOT NULL |
| statement_amount_paise | INTEGER | NOT NULL |
| is_cleared | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| cleared_at | TEXT | nullable |
| note | TEXT | nullable |
| created_at | TEXT | NOT NULL |

UNIQUE `(voucher_id)` — one reconciliation row per voucher.
Index `idx_mally_br_account_cleared` on `(bank_account_id, is_cleared)`.

## 16. mally_migrations

| Column | Type | Constraint |
|---|---|---|
| version | INTEGER | PK |
| applied_at | TEXT | NOT NULL |
| description | TEXT | NOT NULL |

## 17. Registry DB tables (`mally_registry.sqlite`)

### mally_registry_companies

| Column | Type | Constraint |
|---|---|---|
| id | TEXT | PK |
| name | TEXT | NOT NULL |
| sqlite_file_name | TEXT | NOT NULL, e.g. `<uuid>.sqlite` |
| last_opened_at | TEXT | nullable |
| created_at | TEXT | NOT NULL |

## 18. Index summary (one place)

```
idx_mally_companies_name
idx_mally_fy_company
idx_mally_fy_dates
idx_mally_groups_company
idx_mally_groups_parent
idx_mally_accounts_company
idx_mally_accounts_group
idx_mally_accounts_last_used
idx_mally_vouchers_company_date
idx_mally_vouchers_fy
idx_mally_vouchers_type
idx_mally_vouchers_party
idx_mally_vouchers_reversal
idx_mally_lines_voucher
idx_mally_lines_account
idx_mally_lines_company_side
idx_mally_mov_item_date
idx_mally_mov_company_date
idx_mally_mov_voucher
idx_mally_payroll_emp_period
idx_mally_payroll_company_period
idx_mally_audit_entity
idx_mally_audit_time
idx_mally_br_account_cleared
```

## 19. Migration policy

- `SchemaVersion.current = 1` initially.
- `MigrationRunner` reads `PRAGMA user_version`, compares to highest `mally_migrations.version`, and applies missing migrations in order inside a single transaction.
- Each migration is a `struct: Migration` with a numeric version, a description, and a `func up(db: SQLiteDatabase) throws` body.
- Migrations are append-only. Never edit a past migration.
- The first migration, `MigrationV001`, contains the full schema above as one `execute` call (so the DB is created in one shot on first launch).
