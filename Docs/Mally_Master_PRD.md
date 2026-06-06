# Mally Master PRD

The single source of truth for product behaviour. Every screen, every field, every keyboard shortcut, every error message. This document is normative; code must conform to it.

## 0. Product definition

Mally is a 100% offline native macOS desktop accounting application for Indian small businesses, built with Swift 5.9, SwiftUI, and SQLite. It is a simplified, keyboard-driven alternative to TallyPrime, with all entries made manually by a human on a keyboard. It runs entirely on the user's Mac, never connects to the internet, and never sends any data anywhere. Every monetary figure, every quantity, every rate is typed by the user. The system of record is a local SQLite file per company. The app is a digital ledger with strict double-entry validation, not an automated ERP.

## 1. Non-negotiables (summary; full text in `Mally_Rules.md`)

- 100% offline. No `URLSession`. No third-party network libraries. No analytics.
- Money is `Int64` paise everywhere. Never `Double`.
- Every voucher: `Σ debits == Σ credits` before commit. Enforced in service and at SQL trigger.
- No silent deletion. Reversal, disable, end-date only.
- Audit events are append-only.
- Financial-year locks are enforced at SQL trigger level.
- Inventory is optional and is never silently auto-linked.
- Multi-company, one SQLite file per company, isolated.

## 2. User personas

- **Single proprietor / small business owner** running a manufacturing unit, trading house, or service business in India.
- **Accountant** working for the above, entering day-to-day vouchers.
- **Auditor** (read-only use in MVP; audit log viewer + report drill-down).

The app is single-user, offline, and assumes the user is comfortable with a Tally-style keyboard-driven workflow.

## 3. Glossary

| Term | Meaning |
|---|---|
| Paise | 1/100 of a rupee. The atomic money unit Mally stores. |
| Ledger | A leaf account that holds a balance. In Mally, `Account` rows. |
| Group | A non-leaf account used only to aggregate ledgers in reports. In Mally, `AccountGroup` rows. |
| Voucher | A financial event with a header (date, type, number, narration) and two or more lines (debit/credit). |
| Reversal | A paired voucher with flipped lines that "undoes" a previously posted voucher. |
| FY | Indian financial year, 1 April to 31 March. |
| Books begin date | The actual start date of transactions for a company. May differ from the FY start if the company was created mid-year. |
| Locked FY | An FY where all writes are rejected. Set by the user on year-end close. |
| Auto-link | The behaviour of recording a stock movement automatically when a sales/purchase voucher is posted. |

## 4. Data model summary (full schema in `Mally_Schema.md`)

- 1 company → many FYs
- 1 FY → many vouchers
- 1 voucher → 2+ ledger lines
- 1 ledger line → 1 account
- 1 company → 13 default account groups
- 1 account group → many accounts (ledgers) and child groups
- 1 company → 10 default voucher types
- 1 voucher type → many voucher sequences (one per FY)
- 1 company → many inventory items (optional)
- 1 inventory item → many stock movements
- 1 stock movement → optional voucher (the originating voucher, when linked)
- 1 company → many employees
- 1 employee → many payroll entries
- 1 payroll entry → optional voucher (the salary voucher)
- 1 entity → many audit events (append-only)

## 5. Default chart of accounts

Seeded on company creation. Names are English; user can rename later.

### 13 default groups (root groups, no parent)

| Code | Name | Nature |
|---|---|---|
| CAPITAL | Capital Account | liabilities |
| LOANS | Loans (Liability) | liabilities |
| CURRENT_LIAB | Current Liabilities | liabilities |
| DUTIES_TAXES | Duties & Taxes | liabilities |
| FIXED_ASSETS | Fixed Assets | assets |
| INVESTMENTS | Investments | assets |
| CURRENT_ASSETS | Current Assets | assets |
| STOCK_IN_HAND | Stock-in-Hand | assets |
| DIRECT_INCOME | Direct Income | income |
| INDIRECT_INCOME | Indirect Income | income |
| DIRECT_EXPENSE | Direct Expenses | expense |
| INDIRECT_EXPENSE | Indirect Expenses | expense |
| BANK_ACCOUNTS | Bank Accounts | assets |

### 28 default ledgers

| Code | Name | Under | Nature | Opening |
|---|---|---|---|---|
| OWNERS_CAPITAL | Owner's Capital | CAPITAL | liability | 0 / credit |
| PARTNERS_CAPITAL | Partner's Capital | CAPITAL | liability | 0 / credit |
| SECURED_LOAN | Secured Loan | LOANS | liability | 0 / credit |
| UNSECURED_LOAN | Unsecured Loan | LOANS | liability | 0 / credit |
| SUNDRY_CREDITORS | Sundry Creditors | CURRENT_LIAB | liability | 0 / credit |
| SALARY_PAYABLE | Salary Payable | CURRENT_LIAB | liability | 0 / credit |
| DUTIES_N_TAXES | Duties & Taxes (group substitute) | DUTIES_TAXES | liability | 0 / credit |
| CGST_INPUT | CGST Input | DUTIES_TAXES | asset | 0 / debit |
| CGST_OUTPUT | CGST Output | DUTIES_TAXES | liability | 0 / credit |
| SGST_INPUT | SGST Input | DUTIES_TAXES | asset | 0 / debit |
| SGST_OUTPUT | SGST Output | DUTIES_TAXES | liability | 0 / credit |
| IGST_INPUT | IGST Input | DUTIES_TAXES | asset | 0 / debit |
| IGST_OUTPUT | IGST Output | DUTIES_TAXES | liability | 0 / credit |
| CESS | CESS | DUTIES_TAXES | liability | 0 / credit |
| FURNITURE | Furniture | FIXED_ASSETS | asset | 0 / debit |
| PLANT_MACHINERY | Plant & Machinery | FIXED_ASSETS | asset | 0 / debit |
| BUILDING | Building | FIXED_ASSETS | asset | 0 / debit |
| COMPUTER | Computer | FIXED_ASSETS | asset | 0 / debit |
| VEHICLE | Vehicle | FIXED_ASSETS | asset | 0 / debit |
| CASH_IN_HAND | Cash-in-Hand | CURRENT_ASSETS | asset | 0 / debit |
| SUNDRY_DEBTORS | Sundry Debtors | CURRENT_ASSETS | asset | 0 / debit |
| RAW_MATERIAL | Raw Material | STOCK_IN_HAND | asset | 0 / debit |
| FINISHED_GOODS | Finished Goods | STOCK_IN_HAND | asset | 0 / debit |
| SALES | Sales | DIRECT_INCOME | income | 0 / credit |
| SERVICE_INCOME | Service Income | DIRECT_INCOME | income | 0 / credit |
| DISCOUNT_RECEIVED | Discount Received | INDIRECT_INCOME | income | 0 / credit |
| INTEREST_RECEIVED | Interest Received | INDIRECT_INCOME | income | 0 / credit |
| PURCHASE | Purchase | DIRECT_EXPENSE | expense | 0 / debit |
| DIRECT_EXPENSES | Direct Expenses | DIRECT_EXPENSE | expense | 0 / debit |
| SALARY_EXPENSE | Salary Expense | INDIRECT_EXPENSE | expense | 0 / debit |
| RENT_EXPENSE | Rent Expense | INDIRECT_EXPENSE | expense | 0 / debit |
| ELECTRICITY_EXPENSE | Electricity Expense | INDIRECT_EXPENSE | expense | 0 / debit |
| OFFICE_EXPENSE | Office Expense | INDIRECT_EXPENSE | expense | 0 / debit |
| BANK_HDFC | HDFC Bank | BANK_ACCOUNTS | asset | 0 / debit |
| BANK_SBI | SBI Bank | BANK_ACCOUNTS | asset | 0 / debit |

That's 6 GST ledgers, all bankable, all invoiceable. The user adds more ledgers, groups, and stock items as needed.

### 10 default voucher types

| Code | Name | Abbreviation | Affects inventory |
|---|---|---|---|
| journal | Journal | JV | no |
| sales | Sales | SALES | yes |
| purchase | Purchase | PURCH | yes |
| payment | Payment | PAYMENT | no |
| receipt | Receipt | RECEIPT | no |
| contra | Contra | CONTRA | no |
| creditNote | Credit Note | CN | yes |
| debitNote | Debit Note | DN | yes |
| opening | Opening Balance | OPN | no |
| payroll | Payroll | PAYROLL | no |

## 6. Voucher type rules

| Type | Required party account class | Required narration | Number format |
|---|---|---|---|
| journal | no | no | `JV/<fy>/<5-digit>` |
| sales | yes (debtor/asset account) | no | `S/<fy>/<5-digit>` |
| purchase | yes (creditor/liability account) | no | `P/<fy>/<5-digit>` |
| payment | yes (creditor or expense) | no | `PAY/<fy>/<5-digit>` |
| receipt | yes (debtor or income) | no | `RCT/<fy>/<5-digit>` |
| contra | yes (bank or cash) | no | `CON/<fy>/<5-digit>` |
| creditNote | yes (debtor) | yes | `CN/<fy>/<5-digit>` |
| debitNote | yes (creditor) | yes | `DN/<fy>/<5-digit>` |
| opening | no | yes | `OPN/<fy>/<5-digit>` |
| payroll | yes (employee payable or expense) | yes | `PAY/<fy>/<5-digit>` (separate counter from payment) |

The "required party" rule is enforced as a soft warning by the validator. Hard fail only when the type is `creditNote`, `debitNote`, or `payroll`.

## 7. Screen-by-screen specification

### 7.1 CompanyPickerView (launch)

When the app starts and no company is active, this is the first view. It lists companies from the registry DB and offers "New Company" and "Open Backup".

- Layout: centered card. Logo placeholder on top, list of companies below, two buttons at the bottom.
- Empty state: "No companies yet. Click 'New Company' to get started."
- For each company: name, FY range, last opened date. Double-click to switch.
- Buttons: "New Company…" (primary), "Open Backup…" (secondary).
- "Open Backup" opens a file picker for `.mallybackup`. On confirm, calls `RestoreService.restore`.

Keyboard: `Enter` opens the highlighted company; `Cmd+N` triggers "New Company"; `Cmd+O` triggers "Open Backup".

### 7.2 CompanySetupView (wizard)

A 3-step wizard: Company details → Financial Year → Default chart of accounts choice.

**Step 1 — Company details**
- Company name (required, unique, max 120 chars)
- Address line 1, line 2, city, state, pincode, country (default India)
- GSTIN (optional, 15-char format check `##AAAAA####A#A#` if entered)
- PAN (optional, 10-char format check `AAAAA####A` if entered)
- Base currency: INR (read-only)
- Inventory enabled: toggle, default off
- Inventory link mode: dropdown (`manual`, `autoPrompt`, `autoSilent`); default `autoPrompt`; greyed out if inventory is off

**Step 2 — Financial year**
- Label: e.g. `2025-26` (auto-suggested from today's date)
- Start date: defaults to 1 April of the suggested year; editable
- End date: defaults to 31 March of the next year; editable; must be exactly 365 or 366 days from start
- Books begin date: defaults to start date; editable; allowed to be later (e.g. company created in July 2025 → books begin on 1 July)
- Open FY (read-only checkbox, derived from is_locked)

**Step 3 — Default chart of accounts**
- Choice: "Seed with Mally's default 13 groups + 28 ledgers" (recommended) or "Start empty"
- "Back" and "Create Company" buttons

**On Create:**
- Calls `CompanyService.create(companyInput:fyInput:seedDefaults:)` in one transaction.
- DB file is created, schema applied, default voucher types inserted, default groups + ledgers (or empty) inserted.
- Active company is set, active FY is set to the new one.
- Router navigates to the OpeningBalancesView.

### 7.3 FinancialYearSetupView (during onboarding)

Same as the FY step in CompanySetupView, but pre-filled with the current FY's values. Used in two contexts:
- During onboarding (after company is created, before opening balances).
- When a user wants to add a new FY mid-year (rare in MVP, but supported).

For MVP, this view is only used during onboarding. The "add new FY" workflow is in `Settings → Financial Years`.

### 7.4 OpeningBalancesView (wizard)

A table of every ledger, with two editable cells: opening balance (in rupees, formatted Indian grouping) and opening side (`Dr`/`Cr`). Defaults to 0/Dr. Save button is at the bottom.

- "Save opening balances" writes a single `opening` voucher per non-zero ledger, debiting the asset / crediting the liability/equity, and crediting/debiting a balancing "Opening Balance Equity" ledger. The balancing ledger is auto-created on first use and pinned to the CAPITAL group.
- "Skip" leaves balances at 0.
- On save success, navigate to Dashboard.

### 7.5 DashboardView

Top of the home screen. The active company name, active FY range, and today's date in the header.

Tiles (4 across, 2 rows on standard windows):
- **Cash position** — sum of all bank + cash account balances, displayed as a single figure.
- **Receivables** — total balance of all `Sundry Debtors` sub-ledgers (if any).
- **Payables** — total balance of all `Sundry Creditors` sub-ledgers.
- **This month's P&L** — net profit for the current calendar month, with arrow up/down.
- **Stock value** — total value of all stock items (if inventory enabled).
- **Open vouchers** — count of unposted drafts (always 0 in MVP, since drafts are not yet a feature).
- **Audit events (last 7 days)** — count.
- **Backup reminder** — "Last backup: X days ago" or "You haven't backed up in 30 days".

Each tile is clickable and navigates to the relevant report or list.

### 7.6 AccountsHomeView

- Sidebar: tree view of groups + ledgers.
- Top bar: search box, "New Ledger" button, "New Group" button.
- Selecting a ledger opens `AccountEditorView` in a sheet.
- Right pane: details of the selected ledger — code, name, group path, opening balance, current balance (live SQL), is_active, is_bank_account, last_used_at.

#### 7.6.1 AccountEditorView
Fields:
- Code (required, unique within company, alphanumeric + underscore, max 32)
- Name (required, max 120)
- Group (required, dropdown of leaf groups)
- Opening balance (in rupees; side Dr/Cr selector)
- Is bank account: checkbox (when checked, name suggests it goes under BANK_ACCOUNTS but not enforced)
- GSTIN (optional, 15 chars)
- Active: checkbox (default on; unchecking disables)
- Last used: read-only

#### 7.6.2 AccountGroupEditorView
- Code (required, unique)
- Name (required)
- Parent group (dropdown of existing groups; root if blank)
- Nature: assets / liabilities / income / expense
- Active: checkbox
- Sort order: int

### 7.7 VouchersHomeView

- Top bar: voucher type segmented control, FY selector, date range, "New Voucher" button (Cmd+N).
- Table: date, number, type, party, narration, total. Sorted by date desc, then number desc.
- Click row → opens `VoucherEntryView` in read-only mode (in an open FY) or read-only with "Reverse" button (in a locked FY).
- Filters: party, narration contains, amount range, "show reversed only" toggle.

#### 7.7.1 VoucherEntryView (the workhorse)

Layout, top to bottom:

**Toolbar**
- Type selector: dropdown with the 10 types, with abbreviation next to each.
- Date: date picker, default today, but constrained to active FY range.
- Number: read-only, auto-generated on save.
- Reference: free text, optional.
- Save (Cmd+S), Cancel (Cmd+.), Reverse (Cmd+R, only visible if editing an existing voucher)

**Header fields**
- Party/Against: searchable account picker (focusable via Cmd+L). Required for `creditNote`, `debitNote`, `payroll`. Soft warning for the others.
- Narration: multiline text field. Required for `creditNote`, `debitNote`, `opening`, `payroll`.

**Lines table** (Tab/Shift+Tab moves cells; Enter on amount adds a new line)
| # | Account (search picker) | Dr (₹) | Cr (₹) | GST/Tax code (optional) | Cost center (optional) |
|---|---|---|---|---|---|

Empty state: 2 blank lines. Delete row button on each line (X icon).

**Footer (live, updates per keystroke)**
- Debits: `₹1,18,000.00`
- Credits: `₹1,00,000.00`
- Difference: `₹18,000.00` with red dot
- Save button: disabled while difference ≠ 0

**On save success**
- Green banner: "Voucher S/2025-26/00012 saved."
- For `sales` and `purchase` with inventory enabled, the `InventoryLinkPromptView` appears (sheet).

**Errors (exact text)**
- "Debit total (₹1,18,000.00) does not match Credit total (₹1,00,000.00)."
- "Each voucher needs at least two lines."
- "Date 2024-08-15 is outside active financial year 2025-26."
- "Account 'X' is in a locked financial year."
- "Amount must be greater than zero."
- "Account 'X' is a group, not a ledger. Pick a ledger."
- "Duplicate account in lines: 'Cash-in-Hand' appears twice."
- "Credit Note requires a debtor party account."
- "Debit Note requires a creditor party account."
- "Payroll voucher requires the Salary Expense account on at least one line."
- "Narration is required for Credit Note / Debit Note / Opening / Payroll."

**Keyboard shortcuts**
- `Cmd+N` new voucher
- `Cmd+S` save
- `Cmd+.` cancel
- `Cmd+L` focus party picker
- `Cmd+R` reverse (edit mode)
- `Tab` / `Shift+Tab` next/prev field
- `Enter` on amount adds new line
- `Cmd+D` duplicate current line (preserves account and tax code, zeros amounts)
- `Cmd+Shift+P` post inventory link (when prompt is showing)

### 7.8 InventoryLinkPromptView (sheet)

After saving a `sales` or `purchase` voucher, if inventory is enabled, this sheet appears:

- Title: "Record stock movement?"
- Body: A small table of the items this voucher would have moved, computed from any line whose account name matches an inventory item name (e.g. voucher has a credit to "Raw Material" and there's a stock item named "Raw Material"). The table shows: item, qty, unit cost (editable), direction (in/out).
- Buttons: "Yes, save movements" (primary), "No" (secondary), "Don't ask again for this voucher" (tertiary), "Don't ask for any voucher" (tertiary).
- The last option switches the company to `manual` mode and writes an audit event.

### 7.9 ReportsHomeView

Grid of 8 report tiles: Ledger, Trial Balance, P&L, Balance Sheet, GST Summary, Day Book, Outstanding, Stock Valuation. Each tile shows the report's name, an icon, and a one-line description.

### 7.10 LedgerReportView

- Filters at the top: ledger (required, searchable picker), date range (default: current FY), include opening balance (checkbox, default on).
- Table: Date | Voucher # | Type | Particulars | Debit | Credit | Balance.
- Balance column is running, signed. The opening balance is shown in the first row's "Particulars" cell as "Opening Balance".
- Click a row → drill-down to `VoucherEntryView` read-only.

### 7.11 TrialBalanceView

- Filters: as-of date (default: today).
- Table: Account (with group hierarchy indentation) | Debit | Credit.
- Footer: total debits, total credits, diff (must be 0).
- "Export to CSV" button (Cmd+E).

### 7.12 ProfitLossView

- Filters: from-date, to-date (default: current FY).
- Two columns: Income and Expense. Each broken into Direct and Indirect sections.
- Total income, total expense, net profit (or loss).
- "Export to CSV" button.

### 7.13 BalanceSheetView

- Filters: as-of date (default: today).
- Two columns: Liabilities (Capital, Loans, Current Liabilities, Duties & Taxes) and Assets (Fixed Assets, Investments, Current Assets, Stock-in-Hand, Bank Accounts).
- Equity = balancing figure.
- "Export to CSV" button.

### 7.14 GSTSummaryView

- Filters: month picker (default: current month).
- Sections: Output Tax (CGST, SGST, IGST, CESS), Input Tax (CGST, SGST, IGST, CESS), Net Payable.
- A small table per section with the underlying voucher lines.

### 7.15 DayBookView

- Filters: date range (default: today).
- Table: Time, Voucher #, Type, Particulars, Debit, Credit.
- Sorted by created_at asc.

### 7.16 OutstandingView

- Filters: as-of date, type (Receivables / Payables / Both), age buckets (0-30, 31-60, 61-90, 90+).
- Table: Party, Total, 0-30, 31-60, 61-90, 90+.

### 7.17 InventoryHomeView

(Visible only when inventory is enabled for the active company.)

- Tiles: Stock Items, Stock Movements, Valuation, Inventory Settings.
- Each tile opens a sub-screen.

#### 7.17.1 StockItemListView
- Table: Code, Name, Unit, On-hand Qty, Avg Cost, Total Value.
- "New Stock Item" button.
- Click row → StockItemEditorView.

#### 7.17.2 StockItemEditorView
- Code, name, unit, valuation method (FIFO/Weighted Average), active.

#### 7.17.3 StockMovementView
- Filters: item, date range, type.
- Table: Date, Item, Type (in/out), Qty, Unit Cost, Total, Reference Voucher.
- "New Movement" button.
- Click row → read-only details (cannot edit; reverse via a "Reverse" button that creates an opposite movement).

#### 7.17.4 StockValuationView
- Filters: as-of date.
- Table per item: opening qty/value, in, out, closing qty/value, computed using the chosen valuation method.

### 7.18 PayrollHomeView

(Visible only when at least one employee exists.)

- Tiles: Employees, Salary Register, Payroll Settings.
- Each opens a sub-screen.

#### 7.18.1 EmployeeListView
- Table: Code, Name, Designation, Base Salary, Active, Joined On, End Date.
- "New Employee" button.

#### 7.18.2 EmployeeEditorView
- Code, name, designation, PAN, bank account (link to an account with is_bank_account = 1), base salary, joined on, end date (for termination), active.

#### 7.18.3 SalaryVoucherView
- Employee picker, month/year picker.
- Pre-fills gross from base salary. User enters deductions (in rupees; defaults to 0).
- Net = gross - deductions, computed live.
- "Generate Voucher" creates a `payroll` voucher with: Dr Salary Expense / Cr Cash or Bank (whichever the user picks).
- "Save" posts the voucher and writes a payroll_entry row linked to it.

#### 7.18.4 SalaryRegisterView
- Filters: month, year, employee.
- Table: Employee, Gross, Deductions, Net, Voucher #.

### 7.19 BankReconciliationView

- Bank account picker (only `is_bank_account = 1` ledgers).
- As-of date.
- Table: Date, Voucher #, Particulars, Debit, Credit, Cleared (checkbox), Statement date, Statement amount.
- Click row → "Mark cleared" / "Unmark" (Cmd+K).
- Footer: "Uncleared: ₹X | Cleared: ₹Y".

### 7.20 AuditLogView

- Filters: date range, action, entity type, entity id.
- Table: Timestamp, Actor, Action, Entity, Entity ID, "View diff" button.
- Click "View diff" → sheet showing JSON before / JSON after side by side.

### 7.21 SettingsView

Sections:
- **Company** — name, address, GSTIN, PAN. Read-only fields are labelled.
- **Inventory** — toggle on/off, link mode dropdown.
- **Financial Years** — list of FYs with label, dates, locked status, "Lock" / "Unlock" button.
- **Backup & Restore** — "Export Backup" (Cmd+Shift+E), "Open Backup" (Cmd+Shift+I).
- **About** — version, schema version, "Open Application Support Folder" button (for tech support).

## 8. Cross-cutting UX

### 8.1 Keyboard shortcut map (used by `KeyboardShortcutMap`)

| ID | Shortcut | Action |
|---|---|---|
| kNew | Cmd+N | New (voucher / ledger / item) |
| kSave | Cmd+S | Save |
| kCancel | Cmd+. | Cancel |
| kDelete | Backspace | Delete row in table |
| kDuplicate | Cmd+D | Duplicate row |
| kFocusParty | Cmd+L | Focus party picker |
| kFocusNarration | Cmd+I | Focus narration |
| kAddLine | Cmd+Return | Add voucher line |
| kDuplicateLine | Cmd+Shift+D | Duplicate voucher line |
| kSearch | Cmd+F | Focus search bar |
| kCommandPalette | Cmd+K | Command palette (future) |
| kSwitchCompany | Cmd+Shift+C | Switch company |
| kSwitchFY | Cmd+Shift+Y | Switch FY |
| kBackup | Cmd+Shift+E | Export backup |
| kRestore | Cmd+Shift+I | Open backup |
| kToggleSidebar | Cmd+Ctrl+S | Toggle sidebar |
| kPostInventoryLink | Cmd+Shift+P | Post inventory link prompt |

### 8.2 Date format

- Storage: `yyyy-MM-dd` (ISO 8601 date only).
- Display: `dd/MM/yyyy` (e.g. `15/04/2025`). Indian English locale, current time zone.
- Date pickers use the user's locale, but the value passed in is the ISO date.

### 8.3 Money format

- Storage: paise (`Int64`).
- Display: `₹1,18,000.00` (Indian grouping: lakh/crore separators).
- Negative: `₹-1,18,000.00`. Parens `(-1,18,000.00)` are not used in MVP.
- The rupee symbol `₹` is hard-coded; localisation is not in scope.

### 8.4 Empty states

- All lists: "No data yet" centered, with a primary CTA button relevant to the screen.
- Reports before any voucher: "Post a voucher to see this report."

### 8.5 Banners and errors

- `ErrorBanner` appears at the top of the screen for 4 seconds (or until dismissed).
- `BannerKind.success` — green.
- `BannerKind.info` — blue.
- `BannerKind.warning` — amber.
- `BannerKind.error` — red.

### 8.6 Confirmations

- Destructive actions (reverse voucher, disable ledger, close FY) show a `ConfirmationDialog` with the exact consequence in the message.
- Cancel is the default button; the destructive action is `Cmd+Enter` or click.

## 9. Build phases

See `Mally_Architecture.md` §15 and `Mally_Module_Checklist.md` for the file map and acceptance criteria.

## 10. Open items and future work (explicitly NOT in MVP)

These are listed in `Mally_Module_Checklist.md` as deferred. They will not appear in the MVP build:

- Multi-user / roles.
- Cloud sync, online backup.
- GST portal integration.
- E-invoicing.
- Multi-currency.
- Cost centres with budgets.
- Godowns / multiple stock locations.
- Batches and expiry.
- Recurring vouchers (templates handle simple cases).
- Command palette.
- Mobile companion app.
- Internationalisation beyond Indian English.
