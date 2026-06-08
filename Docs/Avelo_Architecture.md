# Avelo Architecture

The shape of the code, the rules between layers, and the patterns repeated everywhere. This document is normative — every code-generation pass must follow it.

## 1. Layered model

```
+--------------------------------------------------------+
|  App/         AveloApp, AppEnvironment, AppRouter      |  ← composition root
+--------------------------------------------------------+
|  Features/    Views + ViewModels per screen            |  ← SwiftUI + @Observable
+--------------------------------------------------------+
|  Core/                                               |
|    Services/   business rules, all validations,       |  ← pure Swift, Sendable
|                audit writes                           |
|    Validation/ validators composed by services        |
+--------------------------------------------------------+
|  Core/                                               |
|    Repositories/  SQL queries, row→struct mapping     |  ← no business rules
|    Database/      SQLiteDatabase wrapper,             |
|                   DatabaseManager, MigrationRunner,   |
|                   BackupService, RestoreService       |
+--------------------------------------------------------+
|  Core/Models/  plain Codable structs                  |
+--------------------------------------------------------+
|  Shared/      formatters, theme, components            |
+--------------------------------------------------------+
|  Resources/   SQL files, default seed JSON            |
+--------------------------------------------------------+
```

**Dependency direction is strictly downward.** A view may import a ViewModel and a service. A service may import a repository and a model. A repository may import a model and the `SQLiteDatabase` wrapper. Models import nothing Avelo-specific.

A view never imports a repository. A repository never imports a service. The data layer never imports SwiftUI.

## 2. Folder structure

```
Avelo/
  App/
  Core/
    Database/
    Models/
    Repositories/
    Services/
    Utilities/
    Validation/
  Features/
    Onboarding/   Dashboard/    Accounts/   Vouchers/
    Reports/      Inventory/   Payroll/   Banking/   Audit/   Settings/
  Shared/
    Components/
    Theme/
  Resources/
    SQL/
    Seed/
```

Every Swift file in `Avelo/` (the app target) compiles into the same module. The folder structure is for human navigation; Swift does not enforce it. The rules in §1 are enforced by code review and by the rules in `Avelo_Rules.md`.

## 3. Composition root

`AveloApp` creates exactly one `AppEnvironment`. `AppEnvironment` is the only place that knows the concrete types of services. Views receive services through `@Environment(AppEnvironment.self)`.

```swift
@main
struct AveloApp: App {
    @State private var env = AppEnvironment.live()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
```

`AppEnvironment.live()` is the only initializer used in the shipped app. A future `AppEnvironment.inMemory` is reserved for previews and is intentionally **not** implemented in MVP.

## 4. Threading and concurrency

- `SQLiteDatabase` is `@unchecked Sendable`. It serializes all `sqlite3_*` calls through a private `DispatchQueue`. No two operations on the same connection run concurrently.
- Services are `final class Sendable`. They are stateless except for their repository dependencies.
- Repositories are `struct Sendable` and stateless. The only state they touch is the `SQLiteDatabase` passed in.
- ViewModels are `@MainActor @Observable`. They call services with `await`. Services do their work on the caller's actor or on the SQLite queue; they do not hop to `@MainActor` themselves.
- SwiftUI views read from `@Observable` ViewModels on the main actor.

This avoids `@MainActor` on services (which would force every repository call to bounce to main) and avoids `actor` services (which would require `await` everywhere with no concurrency benefit in a single-user app).

## 5. Database access

`DatabaseManager` is the only type that opens SQLite files. Its public surface:

```swift
public actor DatabaseManager {
    public init(appSupportDirectory: URL) throws
    public func registry() throws -> SQLiteDatabase           // for the company picker
    public func openCompany(id: UUID) throws -> CompanyHandle
    public func closeCompany(id: UUID)
    public func listCompanies() throws -> [CompanyRegistryEntry]
    public func createCompanyFile(companyId: UUID) throws -> URL
}
```

`CompanyHandle` is a `final class` holding a `SQLiteDatabase` and the company id. It is `Sendable` because the underlying wrapper is. Services take a `CompanyHandle` parameter, not a `SQLiteDatabase`, so the registry DB is never accidentally used for company data.

`SQLiteDatabase` API (only the wrapper may call `sqlite3_*`):

```swift
public final class SQLiteDatabase: @unchecked Sendable {
    public init(path: String, readonly: Bool = false) throws
    public func execute(_ sql: String) throws
    public func query<T>(_ sql: String, bind: [SQLValue] = [], row: (Row) throws -> T) throws -> [T]
    public func queryOne<T>(_ sql: String, bind: [SQLValue] = [], row: (Row) throws -> T) throws -> T?
    public func write(_ block: (SQLiteDatabase) throws -> Void) throws
    public func lastInsertRowID() -> Int64
    public func changes() -> Int32
    public func vacuum() throws
    public func close()
}

public enum SQLValue: Sendable {
    case integer(Int64), real(Double), text(String), blob(Data), null
}

public struct Row {
    public func int(_ i: Int32) -> Int64
    public func int(_ name: String) -> Int64
    public func text(_ i: Int32) -> String
    public func text(_ name: String) -> String
    public func optionalText(_ name: String) -> String?
    public func date(_ name: String) -> Date
    public func date(_ i: Int32) -> Date
    public func bool(_ name: String) -> Bool
    public func data(_ name: String) -> Data
}
```

`write` issues `BEGIN IMMEDIATE`, runs the block, then `COMMIT` or `ROLLBACK` based on whether the block threw.

## 6. MVVM pattern

```swift
@MainActor @Observable
final class VoucherEntryViewModel {
    enum Mode { case create, edit }
    var mode: Mode = .create
    var draft: VoucherDraft = .empty
    var errors: [ValidationError] = []
    var saveBanner: BannerKind? = nil
    var showInventoryPrompt: Bool = false
    var inventoryPromptContext: InventoryPromptContext? = nil

    private let voucherService: VoucherService
    private let accountService: AccountService
    private let inventoryService: InventoryService
    private let companyHandle: CompanyHandle
    private let activeFY: FinancialYear

    init(voucherService: VoucherService, accountService: AccountService,
         inventoryService: InventoryService, companyHandle: CompanyHandle,
         activeFY: FinancialYear) { ... }

    func loadExisting(_ id: Voucher.ID) async { ... }
    func updateLine(_ index: Int, _ mutation: (inout VoucherDraft.Line) -> Void) { ... }
    func addLine() { ... }
    func deleteLine(_ index: Int) { ... }
    func validate() -> ValidationResult { ... }
    func save() async { ... }
    func reverse() async { ... }
}
```

- The view binds the draft to text fields and table rows. It calls `viewModel.updateLine { $0.amountPaise = newValue }`.
- Saving is `await viewModel.save()`. The view shows a banner based on `saveBanner`.
- Validation runs on every change, debounced 200ms, with errors in `viewModel.errors`. The save button is disabled while `errors` is non-empty.
- All async work is `MainActor`-bound because the view model is. Long-running work inside services hops to the SQLite queue but returns on the main actor.

## 7. Error handling contract

```swift
public enum AppError: Error, Sendable {
    case validation(ValidationError)
    case database(SQLiteError)
    case featureUnavailable(String)
    case fileSystem(URL, underlying: String)
    case unexpected(String)
}
```

- Services throw `AppError`. Never a generic `Error` or a `LocalizedError`.
- ViewModels catch `AppError` and convert to a `BannerKind` (a value type with a message, a severity, and a CTA).
- Views render banners using `ErrorBanner`. Views never show raw alerts for business errors.
- Swift `try?` is forbidden in app code. Use `try` and `do/catch` or `Result`.

## 8. Formatters & money

`Currency` is the boundary type:

```swift
public enum Currency {
    public static let paisePerRupee: Int64 = 100

    public static func rupeesToPaise(_ rupees: Decimal) -> Int64
    public static func paiseToRupees(_ paise: Int64) -> Decimal
    public static func formatPaise(_ paise: Int64, style: FormatStyle = .indianGrouping) -> String
    public static func parseRupeeInput(_ userTyped: String) -> Int64?   // nil on invalid
}

public enum FormatStyle {
    case indianGrouping       // 1,18,000.00
    case plain                // 118000.00
    case signedIndianGrouping // +1,18,000.00 / -1,18,000.00
}
```

`Decimal` is the only type used for display math. It never appears in `avelo_*` columns.

## 9. Routing

`SidebarDestination` is a flat `enum`. The router holds a `var selection: SidebarDestination?` property. The view is:

```swift
NavigationSplitView {
    SidebarView(selection: $router.selection)
} detail: {
    switch router.selection ?? .dashboard {
    case .dashboard: DashboardView()
    case .accounts:  AccountsHomeView()
    case .vouchers:  VouchersHomeView()
    case .reports:   ReportsHomeView()
    case .inventory: InventoryHomeView()
    case .payroll:   PayrollHomeView()
    case .banking:   BankReconciliationView()
    case .audit:     AuditLogView()
    case .settings:  SettingsView()
    }
}
```

`AppRouter` also holds `var sheets: [SheetRoute]` for modal presentation (e.g. voucher entry, account editor, company setup wizard).

## 10. Multi-company plumbing

- `AppEnvironment` has `var activeCompany: Company?` and `var activeFY: FinancialYear?`.
- The active company's `CompanyHandle` is cached as `var activeHandle: CompanyHandle?`. Every service method takes the handle as a parameter, so the dependency direction stays clean.
- Switching companies calls `await env.switchCompany(to: companyId)`. This closes the current handle, opens the new one, sets the active FY to the most recent open year, and triggers a router reset to `.dashboard`.
- The registry DB is only used for the company picker and for remembering the last opened company. It never holds ledger data.

## 11. The accounting write pipeline

Every voucher save runs through this exact flow inside `VoucherService.post`:

1. `VoucherDraftValidator.validate(draft, in: companyContext)` returns `ValidationResult`.
2. If invalid, throw `.validation(errors)`. The view model surfaces the errors and the pipeline stops.
3. Open `companyHandle.db.write { ... }`. Inside the block:
   1. Resolve the active FY and verify the date is within `[fy.startDate, fy.endDate]`. Throw if not.
   2. Verify the FY is not locked. Throw if it is.
   3. `nextNumber(companyId, typeCode, fyId)` from `VoucherSequenceRepository`. Increment atomically.
   4. Insert the voucher row. `lastInsertRowID` is ignored; we use the Swift-generated UUID as the PK and pass it through the SQL bind.
   5. Insert all ledger lines with the same voucher id and the same company id.
   6. `VoucherService` computes the running total from the lines and writes it to the voucher row.
   7. `AuditService.record(action: .voucherPosted, entityType: "voucher", entityId: voucher.id, snapshotAfter: voucherJson)` inside the same block.
   8. If inventory is enabled and the voucher type is `sales` or `purchase`, the service returns a `VoucherPostResult` with `inventoryPromptContext` so the view can show the prompt. **The stock movement is NOT auto-posted in MVP.** The user must confirm and post it explicitly.
4. Close the block. `write` commits. Return the saved `Voucher` to the view model.

Reversal follows the same pipeline with `is_reversal = 1` and `reversal_of_id` set. Lines are mirrored (every debit becomes a credit and vice versa, same amounts).

## 12. Report queries

`ReportRepository` exposes methods that return DTOs from `ReportResult`. Each method:

1. Takes a `ReportFilter` (date range, account subset, FY, voucher type subset).
2. Issues a single SQL query that aggregates in SQL.
3. Returns a typed DTO. No `[[String: Any]]` ever crosses the service boundary.

The key SQL patterns are documented inline in `ReportRepository.swift`. The key invariant is: **balance for an account over a period is `SUM(debit_lines) - SUM(credit_lines)` in paise, plus the opening balance paise with its sign.**

## 13. Backup & restore

`BackupService.export(companyId:to: URL) throws`:
1. Asks `DatabaseManager` to flush the WAL by issuing a passive checkpoint.
2. Copies the SQLite file to the destination URL.
3. Writes a sidecar `manifest.json` with schema version, company name, exported-at, SHA-256 of the SQLite file.
4. Returns a `BackupManifest`.

`RestoreService.restore(from: URL, to: appSupportDirectory) throws -> CompanyRegistryEntry`:
1. Validates the sidecar manifest, checks the SHA-256.
2. Copies the file to a new `<uuid>.sqlite` under `Companies/`.
3. Registers the company in the registry DB.
4. Returns the registry entry. The user must explicitly switch to the restored company from the picker.

Restore never overwrites an existing company. The user is asked to pick a target name; collisions fail fast.

## 14. Threading model — concrete rules

- `await` only at service→view model boundaries and at the entry to `DatabaseManager`.
- Inside services, synchronous `SQLiteDatabase` calls are fine. They are serialized by the wrapper.
- No `Task { ... }` fire-and-forget. All work is owned by a view model or by a long-lived service.
- No `DispatchQueue.main.async` calls. Everything main-actor-bound is expressed with `@MainActor`.

## 15. Build phases (recap)

1. Foundation: app shell, DB init, migrations, company picker, company creation, FY creation, opening balances, default chart of accounts, dashboard shell.
2. Accounts: list, editor, hierarchy, opening balance editing, FY lock UI.
3. Vouchers: type list, voucher entry with live balance check, post, edit, reverse, list with filters.
4. Reports: ledger, trial balance, P&L, balance sheet, GST summary, day book, drill-down to voucher.
5. Inventory: company toggle, item CRUD, stock movement entry, auto-prompt integration, valuation report.
6. Banking, reconciliation, backup/restore, audit log viewer.
7. Payroll: employees, salary voucher, monthly posting.
8. Hardening: voucher templates, last-used account sort, multi-line paste, dark mode polish, keyboard shortcut help, full app icon set.

## Appendix A. In-memory AccountTree cache

### A.1 Motivation
A Tally-style UI needs instant drill-down from the Groups list into a Group → its ledgers → a single ledger's running balance. The naïve path (one SQL query per group, one per ledger, one per balance range) is too slow on cold start and on every drill. We solve this by building a single in-memory composite tree per open company and keeping it fresh.

### A.2 Composite structure
`Avelo/Core/Cache/AccountTree.swift` defines:

- `AccountTree` — the root; owns `roots: [GroupNode]`, plus `ledgersById` and `groupsById` lookup tables.
- `GroupNode` — a group; owns `childGroups: [GroupNode]`, `childLedgers: [LedgerNode]`, and a precomputed `balancePaise` = sum of children (recursively).
- `LedgerNode` — a single ledger; owns its `openingBalancePaise`, `movementDebitPaise`, `movementCreditPaise`, and a derived `balancePaise` = opening + debit − credit.
- `LedgerBalance` — small struct used during tree construction to feed in aggregated line sums.

The tree is built bottom-up: leaf ledger nodes compute their balance from `opening_balance_paise` (signed by `OpeningBalanceSide`) and a single SQL aggregation of `avelo_ledger_lines` for that account. Group nodes sum their children. This means the construction cost is O(groups + ledgers) plus one SQL query that aggregates all ledger balances in a single `GROUP BY account_id` scan.

### A.3 Cache lifecycle
`Avelo/Core/Cache/AccountTreeCache.swift` is a `@MainActor` `ObservableObject` owned by `AppEnvironment`. Lifecycle:

1. **Created** in `AppEnvironment.openCompany(_:)` right after `CompanyContext` is set, with the per-company `SQLiteDatabase`.
2. **Loaded** on first access (`ensureLoaded()`); the first call to `findLedger`, `findGroup`, or `breadcrumb` triggers a rebuild if the tree is dirty.
3. **Invalidated** (`invalidate()`) by any write path: `env.markAccountTreeDirty()` is called from `NewVoucherSheet.post`, `EditVoucherSheet.save`, `NewAccountSheet.save`, and `PostSalarySheet.save`.
4. **Disposed** implicitly when `closeCompany()` is called and `accountTree` is set to `nil`.

`@Published tree` and `@Published isDirty` make the cache observable; the Dashboard can show "Tree rebuilt" or "Tree stale" if we want a debug overlay.

### A.4 Accessors
- `findLedger(_: Account.ID) -> LedgerNode?` — O(1) lookup.
- `findGroup(_: AccountGroup.ID) -> GroupNode?` — O(1).
- `groupPath(of: AccountGroup.ID)` / `groupPath(ofLedger:)` — walks up via `parentId`, returns the breadcrumb path.
- `breadcrumb(of: Account.ID)` — renders `"Assets › Bank › HDFC Current"` for status bar / drill UI.
- `allLedgers` — flat list for picker UIs.

### A.5 Append-only ledger interaction
The tree is *derived* from the database. Vouchers are append-only (the `avelo_vouchers.reversal_of_id` column stores a pointer to the reversed voucher; the original is never deleted). The tree reads `SUM(...) FROM avelo_ledger_lines` which naturally includes both originals and their reversals — netting to zero. The cache does not need to track "what changed"; it just rebuilds on invalidate and reads the current full state.

## Appendix B. Global keyboard state machine

### B.1 Motivation
A Tally-style accountant works at the keyboard. We want a global state machine that intercepts function keys and a few chords to open the right sheet or navigate, without binding the same key to conflicting actions in nested views.

### B.2 Components
- `Avelo/Core/Keyboard/KeyboardCommand.swift` — exhaustive enum of every global command (navigation, voucher creation, drill/back, reload, command palette).
- `Avelo/Core/Keyboard/KeyboardContext.swift` (in the same file) — the current state (`.idle`, `.voucherEdit`, `.accountDrill(Account.ID)`, `.search`).
- `Avelo/Core/Keyboard/KeyboardRouter.swift` — `@MainActor` `ObservableObject` that holds `context`, `pendingBuffer` (for the future "type-ahead account code" feature), and `lastCommand`. Views subscribe to it.
- `Avelo/Core/Keyboard/KeyboardMonitor.swift` — installs an `NSEvent.addLocalMonitorForEvents` callback, maps NSEvent key codes to `KeyboardCommand`s, dispatches to the active router.
- `Avelo/Core/Keyboard/KeyboardBridge.swift` — view-side bridge that translates `KeyboardCommand`s into `AppRouter` actions (`router.go(.accounts)`, `router.present(.newPayment)`, etc.) and toggles overlay flags for command palette / quick search / shortcut help.

### B.3 Key bindings
| Combo            | Command                          |
|------------------|----------------------------------|
| Esc              | `goBack`                         |
| Return / numpad Enter | `drillDown`                 |
| R                | `reload`                         |
| F4               | `newVoucher(.contra)`            |
| F5               | `newVoucher(.payment)`           |
| F6               | `newVoucher(.receipt)`           |
| F7               | `newVoucher(.journal)`           |
| F8               | `newVoucher(.sales)`             |
| F9               | `newVoucher(.purchase)`          |
| F10              | `newVoucher(.creditNote)`        |
| F11              | `newVoucher(.debitNote)`         |
| Cmd+1..9         | Sidebar navigation               |
| Cmd+K            | `commandPalette`                 |
| Cmd+/            | `quickSearch`                    |
| Cmd+,            | `showShortcutHelp`               |

These bindings are also surfaced in the macOS menu bar via `CommandMenu("Go")` and `CommandMenu("Voucher")` in `AveloApp.commands`. The function keys *only* show in the menu as text labels (e.g. "Contra (F4)"); the SwiftUI menu has no first-class F-key `KeyEquivalent` constant for the function-key row, so the actual F-key interception is done by `KeyboardMonitor`.

### B.4 Sheet capture
When a sheet/editor is open and the user is typing in a `TextField`, the global monitor would otherwise hijack F5 ("Payment") while the user is typing an amount. The `KeyboardMonitor.setSheetCapture(_:)` flag, exposed via `KeyboardRouter`, suppresses global handling while a sheet is presented. Voucher editor sheets should set this to `true` on appear and `false` on disappear (future work; current implementation provides the flag and the suppression logic).

### B.5 State transitions
`KeyboardRouter.enter(_:)` lets a view push a new context (e.g. `accountDrill(accountId)`) when a user navigates into a ledger. `reset()` is called when the company is closed. The monitor does not care about the context; it just dispatches commands. The bridge decides what to do based on the current `router.presentedSheet` and the command.

This split keeps the monitor stateless, the router a thin observable, and the bridge the one place that knows the SwiftUI navigation graph.
