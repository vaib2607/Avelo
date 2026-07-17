# Avelo Architecture

This document defines Avelo's dependency, lifecycle, persistence, and execution boundaries. It explains how product behavior from `Avelo_Master_PRD.md` is allowed to be implemented. `Avelo_Rules.md` wins on invariants; executable migrations win on schema mechanics; `Avelo_Release_Board.md` wins on readiness.

The complete product and phased execution roadmap is `Avelo_Master_Product_Execution_Plan.md`.

## 1. Layered model

```text
App/                composition, lifecycle, routing, global commands
  ↓
Features/           SwiftUI workflows and @Observable view models
  ↓
Core/Services/      business transactions and policy orchestration
  ↓
Core/Repositories/  SQL operations and strict row mapping
  ↓
Core/Database/      connection, transaction, migration, key, backup/restore
  ↓
Core/Models/        domain values and DTOs

Shared/             reusable UI, formatting, exact utilities, theme
Resources/          versioned seed resources
Vendor/             pinned local SQLCipher source
```

Dependencies point downward. A feature may call a service but does not issue SQL or import a repository. A repository does not enforce a multi-step business workflow. The database layer does not import SwiftUI. Models do not depend on app or feature types.

The folders share one Swift module, so these boundaries are enforced by review and tests rather than compiler visibility alone.

## 2. Composition and application lifecycle

`AveloApp` creates the long-lived `AppEnvironment` and `KeyboardBridge`, injects them into `RootView`, installs the keyboard monitor for the window lifecycle, and owns the macOS command menus.

`AppEnvironment` owns:

- `DatabaseManager` and the registry repository;
- the active `CompanyContext` containing company identity, active FY, and its database connection;
- `AppRouter`, `KeyboardRouter`, global error/banner state, busy state, and data revision;
- the per-company `AccountTreeCache`; and
- cancellable tasks whose results must be rejected when company or FY context changes.

There is one active company context per environment. Opening or switching a company replaces the complete context, resets navigation as required, rebuilds derived state, and cancels work tied to the old identity. Views must not retain a raw database or company ID past that lifecycle.

The self-test path is a separate startup mode. It runs the bundled validation harness and exits without constructing the normal interactive environment.

## 3. Storage and security boundary

`DatabaseManager` is the only component that creates, opens, tracks, and closes app-managed database files.

- `~/Library/Application Support/Avelo/avelo_registry.sqlite` stores company discovery metadata only.
- `~/Library/Application Support/Avelo/Companies/` stores one encrypted SQLite file per company.
- `CompanyKeyStore` keeps a random 32-byte key per company in Keychain.
- `SQLiteDatabase` receives raw key material at the open boundary and validates SQLCipher access before normal queries.
- Recovery keys are user-custody material used to recover an encrypted backup on another Mac. They are checksummed/versioned and never embedded in the backup.
- Backup files contain encrypted database bytes plus a versioned manifest. Logs and UI must never expose raw keys.

Registry metadata is not financial truth. A missing company file produces a typed recovery path; it does not cause Avelo to create a blank replacement under the same registry entry.

## 4. Concurrency and long-running work

`DatabaseManager` is an actor for cross-company file and connection lifecycle. `SQLiteDatabase` is `@unchecked Sendable` because it serializes access internally; callers do not invoke `sqlite3_*` directly or use one connection concurrently outside the wrapper.

UI state, routers, and view models are `@MainActor` and use Observation (`@Observable`). Services and repositories remain UI-independent and `Sendable` where their stored dependencies permit it.

Rules:

- Every `Task` has a visible owner and cancellation point. No unowned fire-and-forget financial work.
- A task captures expected company/FY identity and verifies it again before publishing UI state.
- Migration, backup, restore, large recalculation, repair, and benchmark-scale work use `LongOperationActivityControlling` so App Nap/sleep does not silently suspend a critical operation.
- Cancellation occurs between atomic units, never after partially publishing one unit.
- Progress and recovery are part of the service contract for user-visible long operations.

## 5. Database access and strict decoding

Only `SQLiteDatabase` calls SQLCipher/SQLite C APIs. Its responsibilities include statement preparation/finalization, binding, typed rows, transaction control, pragmas, integrity checks, and connection close.

Repositories:

- accept the correct company database explicitly;
- bind values rather than interpolate user data;
- decode required values with throwing `required*` accessors;
- reject malformed UUIDs, dates, timestamps, enums, booleans, and missing columns;
- apply stable ordering whenever order changes an accounting result; and
- return typed models/DTOs, never untyped dictionaries.

`SQLiteDatabase.write { ... }` is the atomic write boundary. It uses `BEGIN IMMEDIATE` and commits or rolls back based on whether the block throws. A service that spans voucher, workflow, audit, and inventory rows keeps all of them inside the same block.

Direct repository writes are allowed only for a repository's declared persistence operation. They are not an alternate route around service validation, audit, ownership, or fiscal-lock policy.

## 6. Domain-service boundary

Services own multi-step behavior and invariants. Repositories own persistence mechanics. Representative domains are:

- company/FY/account lifecycle;
- voucher, draft, sequence, bill, cheque, cancellation, and reversal workflows;
- item-invoice, inventory movement, valuation, orders, and BOM recipes;
- payroll and bank reconciliation;
- reports, GST documents/exports, backup/restore, and audit.

Services receive the active company identity and database. They validate same-company ownership before write, even where a trigger also enforces it. Every error crossing a service boundary is `AppError` or is immediately wrapped as one.

An operation that returns success has completed every required durable side effect. A placeholder row, empty success result, or swallowed audit/restore failure is not an implementation.

## 7. SwiftUI workflow pattern

Feature views bind to small `@MainActor @Observable` models or to local state backed by services. The view owns presentation and focus; the model owns editable state, validation state, and conversion to domain inputs; services own the transaction.

Submission follows one pattern:

1. Convert text fields into typed boundary values.
2. Revalidate and surface the first actionable error.
3. Use a one-shot in-flight gate.
4. Call one service transaction.
5. On success, clear the draft, invalidate derived state, announce success, and dismiss or continue according to the workflow.
6. On failure, keep the user's input and present `AppError` through the shared host.

Invalid submit buttons remain actionable when activation is needed to explain what is missing. Only a genuine in-flight operation disables repeat activation.

## 8. Routing and capability checks

`AppRouter` owns the selected `SidebarDestination`, one presented sheet route, and report navigation. `SidebarDestination` currently includes Dashboard, Vouchers, Accounts, Reports, Inventory, GST, Payroll, Banking, Audit, and Settings.

Routing does not grant capability. Before exposing or presenting an optional module, the app evaluates the active company's capability. The same decision governs:

- sidebar and macOS menu entries;
- command palette and quick-search results;
- keyboard commands;
- direct sheet/deep-link presentation; and
- service mutation authorization.

Inventory-disabled routing currently has an open production blocker (`AVL-P0-033`). Until it closes, the implementation is not a valid example of this boundary.

## 9. Accounting write pipelines

Account meaning is resolved before a workflow reads or writes financial state. `AccountEligibilityPolicy` evaluates the complete frozen-code group ancestry plus explicit account semantics; picker visibility and service validation call the same policy. Display names never determine cash, bank, party, sales, purchase, tax, stock, payroll, cost, or order eligibility. A retained selection that becomes invalid remains visible with an actionable reason until replaced.

### 9.1 Ledger voucher

`VoucherService` validates the draft and workflow inputs, resolves the exact FY, checks the lock and company, allocates the next number, writes the voucher and lines, writes bill/cheque workflow rows, appends audit evidence, and marks referenced accounts used in one transaction.

The service returns the durable voucher. Legacy automatic inventory-link enum values remain decodable, but production suppresses the incomplete prompt and exposes only manual linkage plus explicit item-invoice entry until `AVL-P0-035` is fully proven.

### 9.2 Item invoice

`ItemInvoiceService` accepts explicit Sales/Purchase item inputs and deterministically derives tax, round-off, ledger, item-line, and inventory effects. Voucher header, ledger lines, `avelo_voucher_item_lines`, stock effects, workflow rows, sequence, and audit commit atomically.

Editing, reversal, cancellation, PDF generation, and restore must preserve the same item/tax lineage. Ledger-mode auto-link and item-invoice mode are separate workflows and must not be conflated.

### 9.3 Edit, reversal, and cancellation

- Open-FY edit is an audited replacement of allowed mutable state and every dependent row.
- Locked-FY records are read-only and use the explicit correction policy.
- Reversal creates linked opposite financial effects; cancellation preserves the voucher and number plus reason, actor, time, and linkage.
- Reports have an explicit policy for reversed/cancelled records.

## 10. Reports and derived state

`ReportRepository` performs authoritative aggregation in SQL and returns typed `ReportResult` values. Report filters include every input that changes meaning: company, FY, dates, ledger/account set, voucher type, opening policy, and any status inclusion.

`ReportService` may cache `(complete filter key, result)` in memory with a data-change token. The cache is disposable and invalidated on writes; it is never persisted as financial truth.

The account tree is also derived state:

- `AccountTree` holds group and ledger nodes plus O(1) lookup maps.
- Construction loads groups/ledgers and uses bounded aggregate queries for FY-scoped movement balances. Large ID sets may be batched; no query-per-ledger loop is allowed.
- `AccountTreeCache` is owned by `AppEnvironment`, keyed to company/FY, invalidated after relevant writes, and discarded on close/switch.
- `AccountTree` exposes hierarchy paths and flat ledger access; the cache exposes lookup/breadcrumb helpers and lifecycle.

Derived state must use checked arithmetic. A cache miss or rebuild cannot change the result.

## 11. Backup and restore

Backup:

1. Validate the company and destination.
2. Hold a long-operation activity and checkpoint/copy a consistent encrypted database into a staging location.
3. Compute checksum and byte count and write a versioned manifest.
4. Atomically publish database and manifest to the user-selected destination.
5. Preserve the prior destination on failure.

Restore:

1. Validate manifest version, file identity, byte count, and checksum before mutation.
2. Stage the imported bytes and open with an existing key or validated recovery key.
3. Reject unsupported future schema; run supported forward migrations on the staged copy.
4. Allocate a collision-safe company identity/name/file and remap every company-scoped table supported by that schema.
5. Rebuild audit/lock triggers as required; run integrity, foreign-key, ownership, FY-overlap, and company-metadata validation.
6. Publish the staged company, Keychain entry, and registry row with compensation on failure.

Restore never overwrites an existing company. Current code does not include `avelo_voucher_item_lines` in the company-ID remap set, so cross-identity restore of item invoices is a release blocker (`AVL-P0-036`) until implementation and regression proof close it. Scratch draft handling must also be explicit: remap validated drafts or discard them intentionally and document that choice.

## 12. Schema evolution

`SchemaVersion.current`, `MigrationRunner.defaultMigrations`, and `MigrationV###` implementations are executable authority. Migrations are forward-only, ordered, individually transactional, and recorded in `avelo_migrations` plus `PRAGMA user_version`.

Migration rules:

- existing rows receive deterministic backfills or the migration fails with the table/column/row context;
- destructive rebuilds stage and validate before replacement;
- every new company-scoped table is added to restore/remap, ownership, fiscal-lock, audit, backup, and schema-drift tests as applicable;
- fresh-create schema and upgraded-schema convergence is proved; and
- docs update in the same change as `SchemaVersion.current`.

The current executable schema is v22. `Avelo_Schema.md` is a readable contract, not a substitute for migrations.

## 13. Audit architecture

`AuditService` appends immutable events inside the transaction that changes the audited state. `AuditRepository` owns storage and chain fields. Database triggers reject update/delete of audit rows.

The chain is HMAC-linked and verified when a company opens. Tamper verification and mutation coverage are different requirements: a correct chain does not prove every mutation emitted an event. Missing action cases and service coverage remain tracked by `AVL-P0-034`.

## 14. Keyboard architecture

`KeyboardMonitor` translates macOS events into `KeyboardCommand`; `KeyboardRouter` holds current command state; `KeyboardBridge` applies commands to `AppRouter`. SwiftUI commands and feature-local shortcuts expose the same actions through native menus and controls.

Resolution order is:

1. an active editor's explicit text/focus behavior;
2. an active sheet/context binding;
3. a module binding; and
4. a global binding.

The monitor's sheet-capture mode prevents global function keys from hijacking text entry. Commands that are impossible for the active capability are rejected rather than routing to hidden UI.

The canonical user contract is in PRD §8.1. Current conflicts between Command-comma Preferences/help, create/edit Return behavior, menu/map backup shortcuts, and contextual Tally aliases remain release work under `AVL-P0-020` and `AVL-P1-044`.

## 15. Production boundary

Architecture acceptance is not a file-layout review. Before production:

- every shipped route reaches a complete service transaction;
- every persistent table participates in migration, restore, ownership, lock, audit, and backup policy as applicable;
- every long operation owns cancellation, progress, App Nap, failure, and recovery behavior;
- current-worktree tests and manual acceptance prove the boundaries on the bundled artifact; and
- Developer ID/notarization or an approved Mac App Store path proves installation and launch on a clean Mac.

Anything incomplete is either hidden behind a complete capability boundary or remains an open release-board item. There is no third state where a visible placeholder counts as shipped.
