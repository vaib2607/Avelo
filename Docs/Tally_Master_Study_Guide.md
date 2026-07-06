# Tally Exhaustive Checklist and Avelo Gap Analysis

## 1. Purpose

This document is a navigation-first checklist built from the two Tally PDFs plus the existing draft notes. It is meant to help you learn:

- every visible menu, dropdown, and screen surface that can be recovered from the source notes
- what each item does
- where each item goes next
- which reports are reachable from it
- what shortcuts and contextual actions are associated with it
- what Avelo already covers, what it partially covers, what is missing, and what is intentionally deferred
- how Tally's Windows-oriented UX maps to Avelo's macOS-native shell

The source PDFs are scan-heavy, so the doc focuses on recoverable menu structure, workflows, report families, shortcut patterns, and screen chrome rather than pretending every pixel-level caption is machine-readable.

## 2. Reading model

Use this format when scanning the checklist:

`Surface -> Where found -> What it contains -> What it opens -> What report it affects -> Shortcut`

Use these labels for status:

- `implemented` means Avelo already has a direct equivalent
- `partial` means Avelo has the core behavior but not the full Tally-style surface or flow
- `missing` means Avelo does not yet have a comparable screen or workflow
- `deferred` means the feature exists in the product strategy but is intentionally out of current scope

## 3. Tally surface inventory checklist

### 3.1 Gateway / home surface

- [ ] Company picker / current company area
  - Where found: startup and top-level home
  - Contains: company name, current period, active books/fiscal year context
  - Opens: company actions and main business areas
  - Affects: everything, because all reports and entries are company-scoped
  - Shortcut: company selection shortcuts and company-info access

- [ ] Main menu bar / module launcher
  - Where found: top-level navigation
  - Contains: masters, vouchers, inventory, reports, statutory, utilities
  - Opens: the relevant module shell
  - Affects: route into all reports and workflows
  - Shortcut: menu accelerators and function-key navigation

- [ ] Right-side or command area actions
  - Where found: gateway buttons and context actions
  - Contains: create company, select company, backup, restore, shut company
  - Opens: company setup and maintenance dialogs
  - Affects: company creation, backup state, restore state
  - Shortcut: Alt-based company info access in classic Tally patterns

- [ ] Footer / button strip / function-key hint bar
  - Where found: bottom of many Tally screens
  - Contains: F-keys, Alt-key actions, accept/cancel hints, report commands
  - Opens: context-specific actions
  - Affects: entry speed and available commands
  - Shortcut: function keys and Alt shortcuts

- [ ] Gateway "Select Company"
  - Where found: gateway action area
  - Contains: company switcher
  - Opens: existing company list
  - Affects: active dataset and report scope

- [ ] Gateway "Create Company"
  - Where found: gateway action area
  - Contains: new company flow
  - Opens: company setup wizard
  - Affects: all future books and reports

- [ ] Gateway "Backup"
  - Where found: gateway action area
  - Contains: backup command
  - Opens: backup dialog
  - Affects: restore safety

- [ ] Gateway "Restore"
  - Where found: gateway action area
  - Contains: restore command
  - Opens: backup import flow
  - Affects: registry and company file creation

### 3.2 Company information and setup

- [ ] Create company
  - Where found: Company Info
  - Contains: company identity, books begin date, financial year, address, tax IDs
  - Opens: company workspace after save
  - Affects: registry, company file, all downstream books
  - Shortcut: Alt+F3 path in classic flow

- [ ] Alter company
  - Where found: Company Info
  - Contains: editable company details and setup
  - Opens: updated company context
  - Affects: company-level behavior and report defaults

- [ ] Shut company
  - Where found: Company Info
  - Contains: close current company session
  - Opens: back to company picker
  - Affects: active workspace only

- [ ] Backup company
  - Where found: Company Info / utilities
  - Contains: export current company data
  - Opens: backup dialog or file save flow
  - Affects: recoverability and migration

- [ ] Restore company
  - Where found: Company Info / utilities
  - Contains: import backup data
  - Opens: restore dialog and company registration
  - Affects: company registry and company file creation

- [ ] Company Info submenu: Select Company
  - Where found: Company Info
  - Contains: open existing company
  - Opens: company picker
  - Affects: active company context

- [ ] Company Info submenu: Create
  - Where found: Company Info
  - Contains: create company form
  - Opens: company setup screen
  - Affects: company file creation

- [ ] Company Info submenu: Backup
  - Where found: Company Info
  - Contains: backup options
  - Opens: save-as backup flow
  - Affects: data portability

- [ ] Company Info submenu: Restore
  - Where found: Company Info
  - Contains: restore options
  - Opens: import backup flow
  - Affects: company registration

- [ ] Company Info submenu: Shut Company
  - Where found: Company Info
  - Contains: close current company
  - Opens: company picker
  - Affects: current session only

### 3.3 Masters

- [ ] Accounts Info
  - Where found: gateway module menu
  - Contains: groups, ledgers, cost centres, cost categories
  - Opens: accounting master creation and alteration screens
  - Affects: trial balance, ledger reports, balance sheet, P&L

- [ ] Groups
  - Where found: Accounts Info
  - Contains: single create, multiple create, display, alter, delete
  - Opens: group hierarchy maintenance
  - Affects: report classification and ledger placement

- [ ] Ledgers
  - Where found: Accounts Info
  - Contains: create, display, alter, delete, opening balance, tax flags
  - Opens: voucher pickers and ledger reports
  - Affects: all accounting reports

- [ ] Inventory Info
  - Where found: gateway module menu
  - Contains: stock groups, stock items, units, categories, godowns
  - Opens: inventory master screens
  - Affects: stock summary, stock movement, valuation

- [ ] Stock Groups
  - Where found: Inventory Info
  - Contains: hierarchy for grouping stock items
  - Opens: stock item classification screens
  - Affects: grouped stock reporting

- [ ] Stock Items
  - Where found: Inventory Info
  - Contains: item name, alias, unit, group, rate, tax, opening quantity
  - Opens: inventory entry and invoicing
  - Affects: stock summary and valuation

- [ ] Unit of Measure
  - Where found: Inventory Info
  - Contains: simple and compound units
  - Opens: measurement setup
  - Affects: item quantity display and invoicing

- [ ] Payroll Info
  - Where found: gateway module menu
  - Contains: employees, salary structure, pay heads, payroll settings
  - Opens: payroll master maintenance
  - Affects: salary posting and payroll reports

- [ ] Accounts Info submenu: Groups
  - Where found: Accounts Info
  - Contains: group list, create, alter, delete
  - Opens: group editor
  - Affects: ledger hierarchy

- [ ] Accounts Info submenu: Ledgers
  - Where found: Accounts Info
  - Contains: ledger list, create, alter, delete
  - Opens: ledger editor
  - Affects: all account-based reports

- [ ] Accounts Info submenu: Cost Centres
  - Where found: Accounts Info
  - Contains: cost-centre list and creation
  - Opens: allocation master screen
  - Affects: dimensional reporting

- [ ] Accounts Info submenu: Cost Categories
  - Where found: Accounts Info
  - Contains: category list and creation
  - Opens: cost category master screen
  - Affects: grouped allocation analysis

- [ ] Inventory Info submenu: Stock Groups
  - Where found: Inventory Info
  - Contains: stock group list and creation
  - Opens: stock-group editor
  - Affects: stock classification

- [ ] Inventory Info submenu: Stock Items
  - Where found: Inventory Info
  - Contains: item list and creation
  - Opens: stock-item editor
  - Affects: item-level reporting

- [ ] Inventory Info submenu: Units
  - Where found: Inventory Info
  - Contains: unit list and creation
  - Opens: unit editor
  - Affects: quantity entry and display

- [ ] Inventory Info submenu: Categories
  - Where found: Inventory Info
  - Contains: category list and creation
  - Opens: category editor
  - Affects: item grouping

- [ ] Inventory Info submenu: Godowns
  - Where found: Inventory Info
  - Contains: location list and creation
  - Opens: storage-location editor
  - Affects: stock-by-location reporting

- [ ] Payroll Info submenu: Employees
  - Where found: Payroll Info
  - Contains: employee list and creation
  - Opens: employee editor
  - Affects: salary processing

- [ ] Payroll Info submenu: Pay Heads
  - Where found: Payroll Info
  - Contains: earnings and deductions setup
  - Opens: pay-head editor
  - Affects: payroll calculations

- [ ] Payroll Info submenu: Salary Details
  - Where found: Payroll Info
  - Contains: salary structure setup
  - Opens: salary-structure editor
  - Affects: salary voucher defaults

### 3.4 Vouchers / transaction entry

- [ ] Accounting vouchers
  - Where found: vouchers menu and function-key bar
  - Contains: Contra, Payment, Receipt, Journal, Sales, Purchase, Credit Note, Debit Note, Reversing Journal, Memo
  - Opens: transaction posting screens
  - Affects: day book, ledger, trial balance, P&L, balance sheet
  - Shortcut: F4-F10 family, Ctrl+F8, Ctrl+F9, Ctrl+F10 patterns

- [ ] Inventory vouchers
  - Where found: inventory voucher area
  - Contains: Purchase Order, Sales Order, Receipt Note, Delivery Note, Rejection In, Rejection Out, Stock Journal, Physical Stock
  - Opens: stock movement and order workflow screens
  - Affects: stock books, movement reports, valuation

- [ ] Voucher entry chrome
  - Where found: voucher screens
  - Contains: header date, voucher number, voucher type, ledger grid, narration, footer totals, key prompts
  - Opens: save, alter, reverse, cancel
  - Affects: all accounting and inventory posting
  - Shortcut: Tab, Enter, Ctrl+Enter, Esc, voucher-type function keys

- [ ] Bill-wise details
  - Where found: voucher entry and ledger configuration
  - Contains: New Ref, Agst Ref, Advance, On Account
  - Opens: invoice allocation prompts
  - Affects: outstanding reports and party balances

- [ ] Cost centres / cost categories
  - Where found: vouchers and accounting features
  - Contains: allocation dimensions and breakup screens
  - Opens: allocation dialog or split prompt
  - Affects: dimensional reporting and internal analysis

- [ ] Voucher class
  - Where found: sales/purchase workflows
  - Contains: template-style line behavior
  - Opens: class-based posting
  - Affects: invoice entry consistency

- [ ] Voucher menu: Contra
  - Where found: Accounting Vouchers
  - Contains: cash-bank transfers
  - Opens: contra voucher screen
  - Affects: cash and bank books

- [ ] Voucher menu: Payment
  - Where found: Accounting Vouchers
  - Contains: payment entries
  - Opens: payment voucher screen
  - Affects: cash/bank outflows

- [ ] Voucher menu: Receipt
  - Where found: Accounting Vouchers
  - Contains: receipt entries
  - Opens: receipt voucher screen
  - Affects: cash/bank inflows

- [ ] Voucher menu: Journal
  - Where found: Accounting Vouchers
  - Contains: adjustment entries
  - Opens: journal voucher screen
  - Affects: non-cash accounting

- [ ] Voucher menu: Sales
  - Where found: Accounting Vouchers
  - Contains: sales invoice entry
  - Opens: sales voucher screen
  - Affects: sales register and tax reports

- [ ] Voucher menu: Purchase
  - Where found: Accounting Vouchers
  - Contains: purchase invoice entry
  - Opens: purchase voucher screen
  - Affects: purchase register and tax reports

- [ ] Voucher menu: Credit Note
  - Where found: Accounting Vouchers
  - Contains: sales return / adjustment
  - Opens: credit-note screen
  - Affects: sales and receivables

- [ ] Voucher menu: Debit Note
  - Where found: Accounting Vouchers
  - Contains: purchase return / adjustment
  - Opens: debit-note screen
  - Affects: purchase and payables

- [ ] Voucher menu: Reversing Journal
  - Where found: Accounting Vouchers
  - Contains: temporary reversal entry
  - Opens: reversing journal screen
  - Affects: adjustment workflows

- [ ] Voucher menu: Memo
  - Where found: Accounting Vouchers
  - Contains: non-posting note
  - Opens: memo screen
  - Affects: draft or review-only workflows

- [ ] Inventory voucher submenu: Purchase Order
  - Where found: Inventory vouchers
  - Contains: purchase ordering
  - Opens: PO screen
  - Affects: order pipeline

- [ ] Inventory voucher submenu: Sales Order
  - Where found: Inventory vouchers
  - Contains: sales ordering
  - Opens: SO screen
  - Affects: order pipeline

- [ ] Inventory voucher submenu: Receipt Note
  - Where found: Inventory vouchers
  - Contains: goods received
  - Opens: receipt-note screen
  - Affects: stock intake

- [ ] Inventory voucher submenu: Delivery Note
  - Where found: Inventory vouchers
  - Contains: goods delivered
  - Opens: delivery-note screen
  - Affects: stock outflow

- [ ] Inventory voucher submenu: Rejection In
  - Where found: Inventory vouchers
  - Contains: rejected goods returned
  - Opens: rejection-in screen
  - Affects: returns and stock correction

- [ ] Inventory voucher submenu: Rejection Out
  - Where found: Inventory vouchers
  - Contains: rejected goods sent back
  - Opens: rejection-out screen
  - Affects: returns and stock correction

- [ ] Inventory voucher submenu: Stock Journal
  - Where found: Inventory vouchers
  - Contains: stock transfer or adjustment
  - Opens: stock-journal screen
  - Affects: stock balances

- [ ] Inventory voucher submenu: Physical Stock
  - Where found: Inventory vouchers
  - Contains: manual stock count
  - Opens: physical-stock screen
  - Affects: stock verification

### 3.5 Reports

- [ ] Trial Balance
  - Where found: reports display
  - Contains: ledger-level debit and credit totals
  - Opens: ledger drill-down
  - Affects: balance verification
  - Shortcut: report navigation keys and drill-down

- [ ] Ledger
  - Where found: reports / account books
  - Contains: voucher history for one ledger
  - Opens: source voucher
  - Affects: account review and reconciliation

- [ ] Day Book
  - Where found: reports
  - Contains: chronological voucher list
  - Opens: voucher details
  - Affects: daily posting review

- [ ] Profit & Loss
  - Where found: reports / statements
  - Contains: income and expense structure
  - Opens: account drill-down
  - Affects: profitability review

- [ ] Balance Sheet
  - Where found: reports / statements
  - Contains: assets, liabilities, equity
  - Opens: group and ledger drill-down
  - Affects: financial position review

- [ ] Cash Book / Bank Book
  - Where found: reports / account books
  - Contains: cash and bank transaction history
  - Opens: voucher details
  - Affects: bank reconciliation support

- [ ] Outstanding reports
  - Where found: reports
  - Contains: receivables and payables
  - Opens: party ledger and invoice details
  - Affects: credit control

- [ ] Stock Summary
  - Where found: inventory reports
  - Contains: stock-on-hand and valuation
  - Opens: item-level reports
  - Affects: inventory control

- [ ] Stock Movement / Item registers
  - Where found: inventory reports
  - Contains: quantity movement history
  - Opens: related vouchers
  - Affects: stock auditability

- [ ] GST reports
  - Where found: statutory / tax reports
  - Contains: tax summary, output/input split, filing-oriented views
  - Opens: tax ledger and voucher drill-down
  - Affects: tax reconciliation

- [ ] Drill-down behavior
  - Where found: most report rows
  - Contains: Enter-to-open source data
  - Opens: voucher or master detail
  - Affects: analysis and correction workflow

- [ ] Report menu: Trial Balance
  - Where found: reports display
  - Contains: balance check by account
  - Opens: ledger detail or subgroup detail
  - Affects: accounting validation

- [ ] Report menu: Day Book
  - Where found: reports display
  - Contains: chronological vouchers
  - Opens: voucher detail
  - Affects: daily review

- [ ] Report menu: Cash / Bank Book
  - Where found: reports display
  - Contains: cash and bank entries
  - Opens: voucher detail
  - Affects: reconciliation and cash control

- [ ] Report menu: Ledger
  - Where found: reports display
  - Contains: account statement
  - Opens: voucher detail
  - Affects: party and account review

- [ ] Report menu: Group Summary
  - Where found: reports display
  - Contains: grouped balances
  - Opens: ledger or subgroup detail
  - Affects: financial statement structure

- [ ] Report menu: P&L
  - Where found: reports display
  - Contains: profit and loss statement
  - Opens: income/expense ledgers
  - Affects: profitability analysis

- [ ] Report menu: Balance Sheet
  - Where found: reports display
  - Contains: asset/liability/equity statement
  - Opens: grouped ledger detail
  - Affects: financial position analysis

- [ ] Report menu: Outstanding Receivables
  - Where found: reports display
  - Contains: customer dues
  - Opens: customer ledger or invoice detail
  - Affects: credit control

- [ ] Report menu: Outstanding Payables
  - Where found: reports display
  - Contains: supplier dues
  - Opens: supplier ledger or invoice detail
  - Affects: payment planning

- [ ] Report menu: Stock Summary
  - Where found: inventory reports
  - Contains: item balances and valuation
  - Opens: item detail
  - Affects: inventory control

- [ ] Report menu: Stock Register / Movement
  - Where found: inventory reports
  - Contains: movement history
  - Opens: movement voucher
  - Affects: stock audit

- [ ] Report menu: GST Summary
  - Where found: statutory reports
  - Contains: tax totals and split
  - Opens: tax-ledger detail
  - Affects: GST reconciliation

- [ ] Report menu: GST Filing Views
  - Where found: statutory reports
  - Contains: filing-oriented summaries
  - Opens: tax breakdown
  - Affects: return prep

### 3.6 Settings, features, and configuration

- [ ] F11 Features
  - Where found: all major screens
  - Contains: accounting features, inventory features, statutory/tax toggles
  - Opens: feature switch dialog
  - Affects: screen availability and workflow paths
  - Shortcut: F11

- [ ] F12 Configure
  - Where found: all major screens
  - Contains: entry behavior, filters, formatting, report view options
  - Opens: configuration dialog
  - Affects: how screens render and behave
  - Shortcut: F12 / Alt+F12 variants

- [ ] Keyboard shortcut help
  - Where found: help or utility areas
  - Contains: function-key map and contextual commands
  - Opens: shortcut reference
  - Affects: speed and discoverability

- [ ] Print / export / zoom / filter controls
  - Where found: reports
  - Contains: output, preview, zoom, filtering, date ranges
  - Opens: print/export panels
  - Affects: report consumption

- [ ] F11 option: Accounting Features
  - Where found: Features
  - Contains: accounting-specific toggles
  - Opens: accounting feature pane
  - Affects: ledger and voucher behavior

- [ ] F11 option: Inventory Features
  - Where found: Features
  - Contains: stock toggles and controls
  - Opens: inventory feature pane
  - Affects: stock screens and vouchers

- [ ] F11 option: Statutory / Taxation
  - Where found: Features
  - Contains: tax options
  - Opens: tax feature pane
  - Affects: GST, VAT, and statutory reporting

- [ ] F12 option: Voucher Entry
  - Where found: Configure
  - Contains: entry behavior options
  - Opens: voucher-entry config pane
  - Affects: keyboard flow and prompts

- [ ] F12 option: Report Configuration
  - Where found: Configure
  - Contains: report filters and display settings
  - Opens: report config pane
  - Affects: report columns and summaries

- [ ] F12 option: Company Configuration
  - Where found: Configure
  - Contains: company behavior settings
  - Opens: company config pane
  - Affects: default workflows

### 3.7 Screen chrome and visual surfaces

- [ ] Header area
  - Contains: screen title, company context, date/period context
  - Purpose: orient the user before data entry

- [ ] Left navigation / module list
  - Contains: gateway paths and module choices
  - Purpose: let the user jump between major areas

- [ ] Footer / function-key strip
  - Contains: save, alter, delete, print, filter, zoom, help
  - Purpose: expose the current screen's shortcuts

- [ ] Table headers / report columns
  - Contains: account, group, date, voucher number, amount, quantity, balance
  - Purpose: show the current report schema

- [ ] Empty-state prompts
  - Contains: no data messages and next-step cues
  - Purpose: guide first-time setup and empty reports

- [ ] Side panel / list pane
  - Contains: module list, report list, account list, or voucher list
  - Purpose: switch context without leaving the screen

- [ ] Context footer actions
  - Contains: save, alter, delete, display, print, filter
  - Purpose: show what the current screen can do next

- [ ] Breadcrumb-like context labels
  - Contains: path / group / company / FY indicators
  - Purpose: show where the user is inside the hierarchy

- [ ] Search / quick lookup entry
  - Contains: search box or command search
  - Purpose: jump quickly to a report, ledger, or master

## 4. Workflow checklist by business task

### 4.1 Company setup workflow

- [ ] Create company
- [ ] Enter company identity and address
- [ ] Set financial year
- [ ] Choose books-begin date
- [ ] Seed chart of accounts
- [ ] Open opening balances
- [ ] Enter first live voucher

### 4.2 Accounting workflow

- [ ] Create groups
- [ ] Create ledgers under correct groups
- [ ] Set opening balances
- [ ] Post vouchers
- [ ] Check ledger report
- [ ] Check trial balance
- [ ] Check P&L and balance sheet

### 4.3 Inventory workflow

- [ ] Enable inventory
- [ ] Create stock groups and items
- [ ] Define units and godowns
- [ ] Post purchase/sales with item rows
- [ ] Record stock movements
- [ ] Review stock summary and movement reports

### 4.4 Payroll workflow

- [ ] Create employee masters
- [ ] Set salary structure
- [ ] Post salary vouchers
- [ ] Review payroll registers

### 4.5 Banking workflow

- [ ] Mark bank-ledger accounts
- [ ] Reconcile statements
- [ ] Review uncleared entries

### 4.6 GST workflow

- [ ] Set tax-ledger structure
- [ ] Post taxable sales and purchases
- [ ] Review GST summary
- [ ] Drill into tax-source vouchers

## 4.7 Screen-by-screen Tally learning path

- [ ] Gateway of Tally
  - route: company picker -> module launcher -> main workspace
  - used for: starting point and module switching

- [ ] Company Info
  - route: create / alter / backup / restore / shut company
  - used for: company management

- [ ] Accounts Info -> Groups
  - route: list -> create -> alter -> delete
  - used for: group hierarchy

- [ ] Accounts Info -> Ledgers
  - route: list -> create -> alter -> delete
  - used for: account masters

- [ ] Inventory Info -> Stock Items
  - route: list -> create -> alter -> delete
  - used for: item masters

- [ ] Accounting Vouchers -> Sales
  - route: voucher type -> ledger/item grid -> save
  - used for: invoice posting

- [ ] Accounting Vouchers -> Purchase
  - route: voucher type -> ledger/item grid -> save
  - used for: purchase posting

- [ ] Reports -> Trial Balance
  - route: report list -> period -> drill-down
  - used for: balancing books

- [ ] Reports -> Ledger
  - route: report list -> account select -> voucher drill-down
  - used for: account review

- [ ] Reports -> Balance Sheet
  - route: report list -> structure view -> detail rows
  - used for: financial position

## 5. Shortcut checklist

Recovered shortcut patterns from the source notes:

- `F1` company / help / contextual function depending on screen
- `F2` change date or period
- `Alt+F3` company info
- `F4` contra
- `F5` payment
- `F6` receipt
- `F7` journal
- `F8` sales
- `F9` purchase
- `F10` reversing journal or report navigation depending on context
- `F11` features
- `F12` configure
- `Alt+C` create master from a field
- `Alt+D` delete where allowed
- `Alt+F12` filter
- `Alt+P` print
- `Alt+Z` zoom
- `Ctrl+F8` credit note
- `Ctrl+F9` debit note
- `Ctrl+N` calculator in classic notes
- `Enter` drill down or accept
- `Esc` back out or cancel
- `Cmd+Enter` save in Avelo-style macOS mapping

### 5.1 Daily-use compatibility matrix

The release requirement is action parity through contextual aliases, not replacement of macOS conventions. Stable backlog ownership is recorded in `Docs/Avelo_Release_Board.md`.

| Workflow | Tally chord | Avelo requirement | ID |
| --- | --- | --- | --- |
| Contra / Payment / Receipt / Journal / Sales / Purchase | F4–F9 | Already opens sheets; must switch type safely inside the active editor. | AVL-P1-044 |
| Sales Order / Purchase Order | Alt+F8 / Alt+F9 | Separate order lifecycle and fulfilment linkage. | AVL-P1-040 |
| Credit Note / Debit Note | Ctrl+F8 / Ctrl+F9 | Add aliases while retaining current F10/F11 bindings; preserve GST linkage. | AVL-P1-040, AVL-P1-016 |
| Stock Journal / Physical Stock | Alt+F7 | Dedicated costed transfer/count workflows. | AVL-P1-040 |
| Receipt/Delivery/Rejection logistics | Alt+F5 / Alt+F6 | Contextual goods-movement voucher family. | AVL-P1-040 |
| Voucher / invoice mode | Ctrl+V | Persisted mode with safe in-editor conversion. | AVL-P1-041 |
| Create master mid-entry | Alt+C | Create/select/return focus without losing draft. | AVL-P1-026 |
| Duplicate voucher | Alt+2 | Fresh IDs/number with source lineage. | AVL-P2-011 |
| Recall narration | Ctrl+R | Scoped history; do not collide with reverse. | AVL-P2-012 |
| Insert while browsing | Ctrl+I | Preserve browser filters/position; do not collide with narration focus. | AVL-P2-013 |
| Audit-safe cancel | Alt+X | Preserve number, history, status, and reason. | AVL-P0-032 |
| Repair/reindex books | Ctrl+Alt+R | Backup-gated dry run and verified repair. | AVL-P1-039 |
| Inline calculator | Ctrl+N | Checked fixed-point result inserted into amount field. | AVL-P2-014 |
| Previous/next voucher | PgUp / PgDn | Continuous browsing with unsaved-state protection. | AVL-P2-013 |
| Cost centre/category/budget | Alt+F6 family | Contextual allocation editor and parallel dimensions. | AVL-P1-010, AVL-P1-011 |
| Report zoom | Alt+Z | Drill and return without losing report context. | AVL-P2-015 |
| Structured export | Alt+E | XML at P1; ASCII/SDF/HTML compatibility at P2. | AVL-P1-043, AVL-P2-017 |
| Email report/voucher | Alt+M | Verified PDF attachment and explicit send confirmation. | AVL-P2-016 |
| Post-date voucher | Alt+S / Ctrl+T | Audited lifecycle distinct from cheque/PDC status. | AVL-P1-041 |
| Comparative columns | Alt+N | Reconciled multi-period report columns. | AVL-P1-036 |

Aliases resolve by active context. Plain text input wins unless the active editor explicitly owns the chord. Shortcut help must disclose collisions and both Tally/macOS bindings.

## 6. Tally Windows UX vs Avelo macOS UX

Tally is historically Windows-first and keyboard-heavy. Avelo is macOS-first and uses SwiftUI conventions, so the doc should not expect a literal clone.

### Windows-first Tally expectations

- function keys are primary navigation
- Alt-key menus are common
- screen chrome often includes footer hints and compact form panels
- menus are dense and modal
- many workflows live inside single-letter or function-key entry points

### macOS Avelo mapping

- sidebar navigation replaces much of the old gateway/menu density
- sheets and split views replace many modal full-screen forms
- toolbar and command palette replace some key-only discovery patterns
- keyboard shortcuts are still preserved, but the visual shell is macOS-native
- reports are presented in a modern SwiftUI layout instead of Tally's classic report pages

### Mapping rule

Preserve the Tally intent:

- quick entry
- drill-down reports
- keyboard-first navigation
- master/voucher/report separation

But render it with Avelo-native conventions:

- sidebar destinations
- sheets for create/edit
- macOS shortcut conventions
- SwiftUI table and split-view patterns

## 7. Avelo gap analysis

### 7.1 Already implemented

- company picker and company scoping
- create/open/backup/restore flows
- dashboard shell
- accounts module with groups and ledgers
- voucher routes and basic entry for the current common voucher types
- report routes for trial balance, P&L, balance sheet, GST summary, day book, ledger, outstanding, and stock valuation
- inventory module
- payroll module
- banking module
- audit module
- settings module
- F4–F11 sheet-opening and macOS navigation shortcuts
- drill-down from reports to source voucher or ledger
- basic financial-year records and voucher/ledger lock triggers

These surfaces are implementation evidence, not a Ready claim. The canonical release board identifies accounting engines and invariants that remain open behind several of these screens.

### 7.2 Partially implemented

- Tally-style gateway/menu bar is mapped into a macOS sidebar rather than a classic Gateway of Tally screen
- classic menu-bar dropdown depth is not mirrored one-for-one
- some Tally screen chrome such as footer function strips are represented through toolbar, shortcut help, and sheets instead
- F4–F9 open voucher sheets, but the editor suppresses function-key switching instead of converting the active voucher flow
- inventory screens and valuation labels exist, but authoritative FIFO/weighted-average layers, residual allocation, ageing consumption, and backdated recalculation remain open (`AVL-P0-010`, `AVL-P0-019`, `AVL-P1-029`)
- trial balance exists, but per-account netting remains a release blocker (`AVL-P0-024`)
- Day Book and report drill-down exist, but the universal browse/edit/cancel/return flow is incomplete (`AVL-P1-037`)
- F11/F12 concepts exist in documentation/shell affordances, but company capabilities and per-screen behavior are not yet consistently separated contextually
- GST summary/invoice export surfaces exist, but e-invoice, monthly return, IMS, annual reconciliation, and full filing contracts remain open (`AVL-P1-001`, `AVL-P1-007`, `AVL-P1-008`)

### 7.3 Missing or not yet equivalent

- continuous Gateway-style access to company context, key reports, and the menu tree without extra navigation (`AVL-P2-019`)
- contextual F11 company features versus F12 per-screen configuration (`AVL-P2-020`)
- universal Day Book browse/edit/cancel flow (`AVL-P1-037`)
- comparative report columns (`AVL-P1-036`)
- full order, stock journal, physical stock, rejection, delivery, and receipt-note family (`AVL-P1-040`)
- voucher classes and automated ledger interest (`AVL-P1-034`, `AVL-P1-035`)
- cost categories in addition to cost centres (`AVL-P1-011`)
- multi-voucher printing, saved voucher/printer profiles, DSC signing, confirmed email, and structured interchange (`AVL-P1-042`, `AVL-P1-043`, `AVL-P2-016`, `AVL-P2-017`)
- daily-use shortcut aliases listed in section 5.1, with macOS bindings retained

### 7.4 Intentionally out of scope or deferred

- cloud sync
- remote login and networked workflows
- cross-company consolidation until `AVL-P2-008`
- legacy ASCII/SDF/HTML export until `AVL-P2-017`; XML interoperability remains a P1 requirement
- expansion from the daily-use shortcut matrix toward the full historical catalogue until `AVL-P2-018`
- any direct Windows clone behavior that would fight macOS conventions

### 7.5 UI / navigation mismatches to keep in mind

- Tally's menu-first flow versus Avelo's sidebar-first flow
- Tally's popup-heavy windows versus Avelo's sheet and split-view design
- Tally's function-key-centric chrome versus Avelo's mixed keyboard plus sidebar navigation
- Tally's dense report pages versus Avelo's modern SwiftUI report views

## 8. Codebase cross-check summary

Based on the current repo:

- `SidebarDestination` exposes dashboard, vouchers, accounts, reports, inventory, payroll, banking, audit, and settings.
- `RootView` wires those destinations into the app shell and exposes sheets for company, vouchers, masters, FY, inventory, payroll, backup, restore, preferences, and help-style utilities.
- `ReportsView` already provides drill-down-capable report families for trial balance, P&L, balance sheet, GST summary, day book, ledger, outstanding, and stock valuation.
- The rules and module checklist confirm routes and happy-path coverage, but several tests currently accept explicit feature deferrals as success.
- The historical baseline is 209 passing tests with 8 skipped benchmark/stress paths. That evidence does not close a readiness item unless the matching `AVL-*` proof gate passes.

The largest gaps are accounting-engine correctness and fiscal/data invariants first, then continuous-flow accountant UX. Visual imitation of Windows-era Tally chrome is secondary and must not displace the P0 catalogue.

## 9. Beginner path

If you want to study the system in order:

1. company and financial year
2. groups and ledgers
3. voucher types
4. day book and ledger reports
5. trial balance
6. profit and loss
7. balance sheet
8. stock masters and inventory vouchers
9. banking and reconciliation
10. payroll and GST

## 10. Evidence note

The PDFs contain many scanned images and repeated screen captures. This checklist consolidates the consistent, recoverable structure from those images into a single map. Where an image-specific label could not be reliably OCRed, the item is recorded by its screen role and workflow function instead of inventing text.
