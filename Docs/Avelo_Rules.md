# Avelo Rules

The non-negotiables. Every code-generation pass, every review, and every change must hold these. If a rule is violated, the change is wrong regardless of how clean the code looks.

## R-1. 100% offline

- No `URLSession`, no `Network`, no `NWConnection`, no Bonjour, no Bluetooth, no IPC over network.
- No `import Network` outside of the sandbox firewall check at startup.
- No third-party HTTP, JSON-over-HTTP, or sync libraries. The dependency list is exactly zero.
- Telemetry, analytics, crash reporting, update checks: all forbidden.
- The app must run, perform all operations, and persist all data with Wi-Fi disabled and the network cable unplugged.
- App Sandbox is ON. Only the app-support directory, the documents directory, and user-selected files are writable.

## R-2. Manual entry, human-typed, every figure

- Every monetary value, every quantity, every rate is typed by a human on a keyboard.
- The app never computes GST for the user. The user types CGST, SGST, IGST as separate lines.
- The app never suggests an item, price, customer, or vendor from history. The user picks or types.
- The app never auto-posts a voucher triggered by a system event.
- Voucher templates (Phase 3) pre-fill a draft that the user must review and save explicitly. Templates never auto-post.

## R-3. SQLite is the system of record

- The SQLite file under `Application Support/Avelo/Companies/<uuid>.sqlite` is the only authoritative store.
- No in-memory cache is ever the source of truth. Views query live.
- Reports are live SQL aggregations. No cached totals, no materialised rollups, no precomputed balances.
- Every write goes through `SQLiteDatabase.write { ... }` which is a `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK` block. Any throw rolls back the entire block.

## R-4. Money is Int64 paise. Never Double.

- All amounts in memory, in SQL columns, in audit JSON, and in DTOs are `Int64` paise.
- ₹1.00 = `100` paise. Display divides by 100 and uses an Indian-locale formatter.
- `Double` and `Float` are banned in any code path that touches money. `Decimal` is allowed only in the boundary formatter layer and only for display rounding, never for storage or arithmetic.
- Overflow assertion: every aggregation asserts `result <= Int64.max / 2` after every `SUM()`. If it fires, the books are corrupt and the assertion is the safety net.

## R-5. Double-entry is mandatory before commit

- For every voucher: `SUM(debit_lines.amount_paise) == SUM(credit_lines.amount_paise)`.
- Validation runs in `VoucherService.validate` before the DB write begins. The DB write itself is rejected by a trigger if violated.
- Zero-amount lines are rejected.
- Single-line vouchers (only a debit, no credit) are rejected.
- Duplicate account in the same voucher is rejected.

## R-6. Financial-year boundaries and locks are enforced

- A voucher can only be posted if its date falls within an open financial year for the company.
- A financial year is locked when the user explicitly closes it. Locked years reject all inserts, updates, and deletes on vouchers, accounts (for that year), and inventory movements.
- Year-end close is a separate user action. It creates the next year's opening balances by carrying forward balance-sheet accounts.
- Switching the active FY in the app only changes the view filter; it never re-locks an already-locked year.

## R-7. Inventory is optional and never pollutes accounting-only workflows

- A company has `is_inventory_enabled: Bool`. When `false`, the entire Inventory sidebar entry is hidden, the Stock Item and Stock Movement screens are unreachable, and `InventoryService` is constructed but no-op on its public methods.
- When `true`, the company has `inventory_link_mode: enum { manual, autoPrompt, autoSilent }`.
- The default is `autoPrompt`. `autoSilent` is opt-in. The user must explicitly enable it.

## R-8. Auto-link inventory behavior is never silent by default

- In `autoPrompt` mode, after a successful `Sales` or `Purchase` voucher save, the UI presents a sheet: "Record stock movement for these items?". The user must click Yes / No / Don't ask again.
- "Don't ask again" switches the company to `manual` mode and writes an audit event.
- `autoSilent` mode is a separate, explicit opt-in, and the audit log records every auto-created stock movement.

## R-9. Audit logging for every financially meaningful action

- The following actions write to `audit_events` in the same transaction as the action itself: create company, create FY, close FY, create account, edit account, disable account, create voucher, edit voucher, reverse voucher, create stock item, record stock movement, post salary, post bank reconciliation match, restore from backup.
- Each event stores: timestamp, actor (always "user" in MVP), action enum, entity type, entity id, JSON snapshot_before, JSON snapshot_after, and an optional reason.
- Audit events are append-only. There is no UI path to delete or edit an audit event. The DB trigger rejects such updates.
- Audit events never block the user's primary action. They live in the same transaction but are written last.

## R-10. No silent deletion, ever

- Vouchers are never deleted. Reversal creates a paired voucher with the same lines flipped and a `reversal_of_id` pointer to the original. The original remains queryable.
- Accounts are never hard-deleted. They are disabled (`is_active = 0`) and kept for historical reporting.
- Stock movements are never deleted. A reversal movement of opposite sign cancels the original.
- Employees are never deleted. Termination is `end_date` set on the employee record.

## R-11. Reversal is the only edit mechanism for posted vouchers in a locked FY

- A voucher in a locked FY is read-only. To "change" it, the user reverses it and posts a corrected one in an open FY with a back-dated `date`.
- A voucher in an open FY can be edited in place, but every edit writes a full audit snapshot.

## R-12. Multi-company from day one, isolated files

- Each company is one `.sqlite` file at `Application Support/Avelo/Companies/<uuid>.sqlite`.
- A small `registry.sqlite` in `Application Support/Avelo/` lists known companies for the picker. It never holds financial data.
- The app never opens two company databases in the same transaction. Cross-company reports are explicitly out of scope.

## R-13. Reports are pure functions of stored entries

- Every report query joins `entries` and `transactions` and computes balance on the fly.
- There is no `balances` table. There is no `materialised_view`. A report for 5 years of data is recomputed on each request and is correct to the last transaction.
- Report filters (date range, account, FY, voucher type) translate to SQL `WHERE` clauses. The Swift code does not loop over rows to compute totals.

## R-14. Naming freeze

- All type, method, table, and column names are defined in `Avelo_Naming_Freeze.md`. Renaming requires updating the freeze document first. Ad-hoc renames in later passes are rejected.

## R-15. No placeholders, no TODOs, no `fatalError("Not implemented")`

- Every file is complete. Every public method has a body.
- If a feature is genuinely out of scope, it is documented in `Avelo_Module_Checklist.md` as "deferred to Phase N" and the corresponding public API is either absent or returns a typed `AppError.featureUnavailable`.
- The Swift compiler must produce zero warnings on a clean build with `-Xfrontend -warn-concurrency -strict-concurrency=minimal` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

## R-16. SwiftUI lifecycle, @Observable ViewModels

- The app is SwiftUI on macOS 14, lifecycle `WindowGroup`, no `AppDelegate` unless platform forces it.
- ViewModels use the `@Observable` macro and `@MainActor`. Services are plain `Sendable` classes or `actor`s.
- `ObservableObject` and `@Published` are forbidden.
- No third-party SwiftUI libraries.

## R-17. Errors are typed, not exceptions at the boundary

- Services throw `AppError` (a structured enum with associated values for each failure mode). ViewModels catch and convert to a displayable `ErrorBanner.Model`. Views never `try?` silently.

## R-18. Keyboard-first, mouse-tolerated

- Every primary action has a keyboard shortcut. The shortcut is shown in the UI alongside the button label.
- Tab order is explicit. The default `Tab` key behaviour is overridden where necessary to follow the data-entry flow.
- `Enter` on a voucher amount adds a new line. `Cmd+Enter` saves. `Esc` cancels.
