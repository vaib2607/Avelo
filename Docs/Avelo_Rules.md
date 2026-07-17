# Avelo Rules

These are Avelo's non-negotiable product and engineering invariants. A change is not releasable when it violates a rule, even if its local tests pass. `Avelo_Master_PRD.md` defines user-visible behavior, `Avelo_Schema.md` describes persistence, and `Avelo_Release_Board.md` owns the readiness verdict.

The consolidated product roadmap is `Avelo_Master_Product_Execution_Plan.md`.

## R-1. Avelo is fully offline

- Shipped code must not use `URLSession`, `Network`, `NWConnection`, web views, telemetry, analytics, crash reporting, online licensing, update checks, or any other network transport.
- `Package.swift` must contain no externally resolved package dependency. Version-pinned source compiled from `Vendor/` is permitted; runtime network access is not.
- SQLCipher may be compiled locally against Apple CommonCrypto. OpenSSL and hosted services are out of scope.
- The app must create, open, post, report, back up, restore, and recover with networking disabled.
- `make net-check` must report zero shipped-code matches before release.

## R-2. User intent is explicit; derivation is deterministic and reviewable

- A user explicitly supplies or selects every business input: party, account, item, quantity, rate, date, tax treatment, and posting intent.
- Avelo may deterministically derive GST, CESS, taxable value, valuation, COGS, round-off, totals, and balancing presentation from explicit inputs plus stored master data.
- Derived values must be visible before or immediately after posting, reproducible from stored inputs, and covered by golden tests.
- Avelo never infers an item, party, price, tax treatment, or vendor from an account name or usage history.

Account eligibility is a shared policy, not view-local filtering. Account meaning is resolved through the full group hierarchy and explicit role/profile data. Picker visibility, posting validation, import validation, edit validation, and restore validation use the same policy.

Future extensions are restricted to approved typed service commands and datasets. They may not access arbitrary SQL, network transports, processes, DLLs, COM, unrestricted files, or bypass ownership, balancing, fiscal locks, checked arithmetic, or audit requirements.
- Templates and recalled values create reviewable drafts. No system event posts a voucher automatically.

## R-3. SQLite is the system of record

- Each company database under `~/Library/Application Support/Avelo/Companies/` is authoritative for that company's books. `avelo_registry.sqlite` contains discovery metadata only.
- App-managed company databases are SQLCipher-encrypted with a random per-company key stored in Keychain. A recovery key is shown only through the explicit recovery workflow.
- In-memory state and disposable change-token caches may accelerate reads, but they are never authoritative or persisted as financial truth.
- Every financial write uses `SQLiteDatabase.write { ... }`. A thrown error rolls back the transaction.

## R-4. Money and quantity arithmetic is exact

- Money is `Int64` paise in models, SQL, audit snapshots, services, and report DTOs.
- `Double` and `Float` are forbidden on money paths. `Decimal` is allowed only at parsing and display boundaries, never as authoritative storage.
- Fractional quantities and UOM conversions use `ExactQuantity` or an equivalent checked rational/fixed-point representation. Legacy `REAL` columns are migration input only.
- Addition, subtraction, multiplication, division, absolute value, conversion, aggregation, and formatting use checked, throwing operations. Overflow, underflow, divide-by-zero, and `Int64.min` fail with typed errors.

## R-5. Double-entry is mandatory before commit

- Every posted voucher has at least two positive ledger lines and equal debit and credit totals.
- The approved posting pipeline validates, allocates the number, writes the voucher and lines, writes related workflow rows, and records the audit event atomically.
- Callers may not bypass the posting pipeline with direct repository writes.
- SQLite triggers enforce company ownership, fiscal locks, and other row-local invariants. Balance is enforced by the only allowed atomic posting pipeline and reconciliation tests because SQLite has no deferred aggregate constraint for voucher lines.

## R-6. Financial-year state is explicit and enforced

- A voucher date must resolve to exactly one financial year for its company; overlap or ambiguity fails closed.
- Locking an FY freezes all dated financial mutations covered by the lock contract. Unlocking is explicit and audited.
- Closing an FY is a separate action. It publishes the next FY's opening snapshot exactly once; reopen removes that published snapshot; re-close is idempotent.
- Switching the active FY changes context only. It does not lock, unlock, close, reopen, or rewrite history.
- Corrections to a locked period use a linked reversal or correction in an open period. Avelo never backdates a new mutation into a locked FY.

## R-7. Optional modules have complete capability boundaries

- When inventory is disabled, Inventory is absent from the sidebar, menus, command palette, quick search, keyboard routing, sheets, and direct/deep-link entry.
- Inventory services reject mutation when the company capability is disabled. Hiding UI alone is insufficient.
- The same rule applies to every future optional module: one capability decision controls every entry point and service boundary.

## R-8. Inventory linkage is never inferred or silently incomplete

- `manual` keeps ledger vouchers and stock movements separate.
- Item-invoice mode is explicit: the user selects item, quantity, rate, party, and sales/purchase ledger; Avelo derives reviewable tax and valuation lines and posts accounting, item lines, and stock effects atomically.
- `autoPrompt` may ship only when the prompt collects explicit item/quantity/direction inputs, records the user's decision, and handles edit, reversal, cancellation, restore, and audit consistently.
- `autoSilent` may ship only after deterministic mapping, preview/consent, reversal, audit, and accountant acceptance are proved. Until then it must be unavailable in production UI.
- Account-name matching or history-based item inference is forbidden.

## R-9. Every meaningful mutation is audited atomically

- Every shipped financially or operationally meaningful mutation has an `AuditAction` and one immutable audit event in the same transaction.
- The event records actor, action, entity, timestamp, before/after snapshots as applicable, and a reason where policy requires one.
- The audited state must be known before the event is appended. Any later transaction failure rolls back both the mutation and the event.
- Audit append failure fails the primary mutation; it is never swallowed.
- The HMAC-linked chain detects mutation, deletion, insertion, reordering, and whole-chain replacement under the documented key/anchor model.

## R-10. No silent deletion

- Posted vouchers are reversed or cancelled with immutable reason, actor, timestamp, numbering, and linkage. Numbers are never reused.
- Accounts and stock items are disabled or archived when history references them.
- Stock corrections use linked opposite movements or deterministic replay, not row deletion.
- Employees terminate through an end date and status, not destructive deletion.

## R-11. Posted-history edits follow fiscal policy

- An open-FY voucher may be edited only through the audited service path and must retain complete before/after evidence.
- A locked-FY voucher is read-only. Correction uses the locked-period workflow defined by R-6.
- A reversal, cancellation, or edit must update every dependent bill, cheque, item, stock, valuation, report, and audit record atomically or fail closed.

## R-12. Company data is isolated

- One company maps to one encrypted SQLite file; financial tables do not live in the registry database.
- All IDs referenced by a mutation must belong to the active company. Repositories and services validate ownership, and schema triggers enforce it where possible.
- A transaction never spans two company databases. Cross-company consolidation is out of scope until explicitly designed.

## R-13. Reports are reproducible from stored entries

- Authoritative report aggregation lives in SQL over stored vouchers, ledger lines, opening snapshots, workflow rows, and stock layers.
- Swift may assemble DTOs and perform checked reconciliation, but it must not replace the report's query semantics with hidden mutable totals.
- A disposable cache key includes company identity, FY/date/filter inputs, and a data-change token. Writes invalidate affected cache entries.
- Every report exposes its filters and reconciles to the ledger or stock source appropriate to that report.

## R-14. The naming freeze is explicit, not imaginary

- Only symbols and identifiers explicitly listed in `Avelo_Naming_Freeze.md` are locked.
- SQL table and column identifiers are governed by migrations plus `Avelo_Schema.md`.
- A rename updates code, tests, migrations/compatibility policy, and the naming document in one change. Ad-hoc aliases are not a substitute.

## R-15. Shipped paths are complete

- Shipped source contains no `TODO`, `FIXME`, placeholder success, or `fatalError("Not implemented")` path.
- A deferred capability is absent from production entry points or returns a typed `AppError.featureUnavailable`; it is tracked on `Avelo_Release_Board.md`.
- Release builds run with `-Xswiftc -warnings-as-errors`. Concurrency warnings and skipped tests are release failures unless explicitly approved and recorded.

## R-16. SwiftUI state follows one lifecycle

- Avelo targets macOS 14+ with SwiftUI and Observation (`@Observable`). View models and UI routers are `@MainActor`.
- `ObservableObject`, `@Published`, `@EnvironmentObject`, singleton app state, and third-party UI frameworks are forbidden in shipped paths.
- Background database work has an owned task/activity lifetime, reports progress where needed, and never publishes stale company context.

## R-17. Errors are typed and actionable

- Service boundaries throw `AppError` or wrap lower-level errors immediately.
- Views show an actionable banner, sheet, or global error host. Business failures are not silently discarded with `try?`.
- Corrupt dates, enums, booleans, UUIDs, schema versions, required columns, and recovery material fail closed rather than becoming valid-looking defaults.

## R-18. Core accounting is keyboard-completable and accessible

- Every primary accounting action is keyboard-completable and exposes its shortcut in UI/help.
- Voucher entry uses one canonical contract: plain Return advances or adds a line; Command-Return posts/saves; Tab and Shift-Tab traverse predictably; Escape cancels or backs out safely.
- Context-specific bindings beat global bindings; ordinary text input wins unless the active editor explicitly owns a command.
- Keyboard-only, VoiceOver, visible-focus, contrast, resizing, non-color status, and error-recovery acceptance are required for every shipped workflow.

## R-19. Persistence evolves forward and restores fail closed

- Schema migrations are ordered, forward-only, individually transactional, and recorded in both `PRAGMA user_version` and `avelo_migrations`.
- The executable migration list and `SchemaVersion.current` are authoritative. `Avelo_Schema.md` must match them at release cut.
- Backup manifests are versioned and checksummed. Restore stages changes, remaps every company-scoped table introduced by every supported schema version, recreates required triggers, and passes integrity, ownership, and foreign-key checks before publication.
- Unknown future schema versions, wrong keys, partial files, unsupported manifests, and unmapped tables are rejected without replacing the original company.

## R-20. “Implemented” is not “release-ready”

- `Avelo_Release_Board.md` is the canonical readiness verdict. `Avelo_Status_Checklist.md` summarizes human state; `Avelo_Execution_Checklist.md` owns next actions and evidence.
- A feature ships only after current-worktree automated proof plus all applicable accountant, operator, keyboard, accessibility, visual/document, and distribution acceptance.
- Evidence records commit/worktree identity, date, machine/toolchain, command, result, skipped tests, and artifact identity. Old evidence is historical context, not current release proof.
- Public production requires an approved distribution path, release metadata, signing/notarization or Mac App Store acceptance, clean-Mac install/launch proof, rollback artifacts, and an incident/support owner.
