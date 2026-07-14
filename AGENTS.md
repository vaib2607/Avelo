# Avelo Repository Instructions

These instructions define how agents should take Avelo from its current state to a release-grade macOS application. Keep this file stable and put changing feature status, evidence, and priorities in the release documents named below.

## Authority and Source-of-Truth Order

Before making a non-trivial change, read the documents relevant to the task in this order:

1. `Docs/Avelo_Master_PRD.md` — normative product behaviour and user workflows.
2. `Docs/Avelo_Rules.md` — non-negotiable product, accounting, security, and engineering rules.
3. `Docs/Avelo_Naming_Freeze.md` — locked type, method, table, and column names.
4. `Docs/Avelo_Architecture.md` — layer boundaries, dependency direction, concurrency, and data flow.
5. `Docs/Avelo_Status_Checklist.md` — current human-readable implementation and release state.
6. `Docs/Avelo_Execution_Checklist.md` — current executable queue and proof still required.
7. `Docs/Avelo_Release_Board.md` — canonical readiness catalogue, severity, dependencies, and release verdict.
8. `Docs/DX.md` — supported development, verification, and benchmark workflow.

Use `Docs/Avelo_Schema.md`, `Docs/Avelo_Module_Checklist.md`, `Docs/Avelo_Operator_Guide.md`, and feature-specific plans when the task touches those areas. If two normative documents conflict, do not choose silently. Identify the conflict and request a ruling before implementing behaviour that depends on it.

Do not copy the changing P0/P1/P2 backlog into this file. A route, model, test, historical completed item, or partially implemented screen is not proof that a feature is release-ready.

## Work Selection and Release Priority

- Inspect the current worktree before selecting new work. Finish or safely isolate overlapping active work before starting an unrelated backlog item.
- Use `Docs/Avelo_Execution_Checklist.md` for the next concrete action and respect its dependency order.
- Close P0 release blockers before P1 rollout work. Do not select P2 work unless the user requests it or it is required by a blocking dependency.
- Distinguish `Implementation remaining`, `Proof remaining`, and `Manual acceptance remaining`. Do not rewrite completed implementation when only proof or acceptance remains.
- Automated tests cannot satisfy accountant, operator, keyboard, visual, accessibility, printing, sleep/App Nap, or clean-device acceptance gates.
- Conditional and deferred modules must not appear in shipped sidebar routes, menus, command palettes, search results, shortcuts, or sheets unless they pass the same release gates as core modules. Clearly label any intentionally visible conditional workflow.
- Do not treat a placeholder, `featureUnavailable`, schema field, model, service, or route as a shipped workflow.

## Project Structure and Dependency Boundaries

- `Avelo/App/`: composition root, application lifecycle, environment, and routing.
- `Avelo/Features/`: SwiftUI views and `@MainActor @Observable` view models.
- `Avelo/Core/Services/`: business rules, validation orchestration, transactions, and audit writes.
- `Avelo/Core/Repositories/`: SQL queries, persistence operations, and row-to-model mapping.
- `Avelo/Core/Database/`: SQLite/SQLCipher access, migrations, backup, restore, and file lifecycle.
- `Avelo/Core/Models/`: plain value types with no Avelo-specific dependencies.
- `Avelo/Core/Validation/`: reusable business validators.
- `Avelo/Core/Utilities/`: focused cross-cutting utilities such as checked arithmetic and formatting.
- `Avelo/Shared/`: reusable components, formatting, and theme tokens.
- `Avelo/Resources/`: SQL and seed resources.
- `Tests/AveloTests/`: unit, service, repository, migration, restore, view-model, and regression tests.
- `Vendor/SQLCipher/`: vendored and pinned SQLCipher source.

Dependencies flow downward. Views do not access repositories or SQLite directly. View models coordinate UI state and call services. Services own business decisions and transactional orchestration. Repositories do not invent business rules. Only the database layer calls `sqlite3_*`. Core data layers do not import SwiftUI.

Concrete dependency construction belongs in `AppEnvironment`. Company financial operations use the correct `CompanyHandle`; never substitute the registry database. Do not make services `@MainActor` merely to silence concurrency diagnostics. Preserve the threading contract in `Docs/Avelo_Architecture.md`.

## Non-Negotiable Implementation Rules

- Avelo is fully offline. Do not add runtime network access, telemetry, analytics, crash reporting, remote update checks, or externally resolved SwiftPM packages.
- Vendored, version-pinned source such as `Vendor/SQLCipher` is permitted. New vendored code requires explicit security, licence, build, and maintenance review.
- SQLite is the source of truth. Do not add authoritative in-memory caches, stored report totals, materialised balances, or derived financial state that can drift from entries.
- Store and calculate money as checked `Int64` paise. Never use `Double` or `Float` on a money path. Handle `Int64.min`, multiplication, addition, subtraction, absolute values, reductions, and SQL aggregates without traps, wrapping, saturation, or silent precision loss.
- Enforce double-entry balance, company ownership, financial-year resolution, fiscal locks, voucher numbering, and audit requirements in service and database paths—not only in the UI.
- Financial mutations and their audit events must be atomic unless a documented batch contract explicitly defines durable chunk boundaries.
- Posted financial history is reversed, cancelled, or disabled according to the product rules; it is never silently or destructively deleted.
- Reports are reconciled live from persisted entries and transactions.
- Persisted malformed dates, UUIDs, enums, columns, ownership references, and numeric values fail closed with actionable typed errors.
- Services throw typed `AppError`. Do not suppress failures with `try?`, empty catches, fallback identifiers, or invented default financial values.
- View models use `@MainActor @Observable`. Do not introduce `ObservableObject`, `@Published`, or `@EnvironmentObject` into shipped paths.
- Do not add TODOs, FIXMEs, incomplete public APIs, placeholder implementations, or `fatalError("Not implemented")`.

## Database, Migration, Backup, and Restore Contract

Before changing persisted data, inspect the schema, naming freeze, migration runner, database triggers, backup manifest, restore staging, seed data, and relevant compatibility tests.

- Use forward-only migrations. Do not rewrite a migration that may have shipped unless the user explicitly approves a compatibility strategy.
- Fresh database creation and upgrade from every supported prior schema must produce equivalent current schemas, triggers, indexes, and invariants.
- A new financial write path must extend company-ownership, fiscal-lock, audit, and integrity protections where applicable.
- Test the migration using realistic older database fixtures, not only a fresh in-memory database.
- Test failure and cancellation at each destructive boundary. The result must be either the valid old state or the valid new state, never a partial registry/file/Keychain/database state.
- Backup and restore changes must preserve manifest-version checks, checksum and byte-count validation, company identity, encryption, staging, atomic replacement, cleanup, and recovery-key behaviour.
- Restore or migration must not silently repair corrupt financial history. Fail closed and provide an operator recovery path.
- Persistent model changes must consider drafts, seed data, reports, exports, audit snapshots, restore remapping, and company isolation.

## Swift and UI Conventions

Follow existing Swift formatting: 4-space indentation, small focused types, and file names matching the primary type. Use `PascalCase` for types, `camelCase` for methods and properties, and `snake_case` for SQL tables and columns. Update the naming freeze before an approved locked-symbol rename.

Match surrounding architecture before introducing a new abstraction. Prefer explicit domain types and small testable methods. Avoid broad refactors mixed with behaviour changes.

Every shipped workflow must be evaluated for:

- Complete keyboard operation, including Tab, Shift-Tab, Return, Escape, default actions, and documented shortcuts.
- Correct focus restoration when sheets, validation errors, or mid-flow master creation interrupt entry.
- One durable action for one visible submission; repeated keys or clicks must not create duplicate financial records.
- VoiceOver labels, values, grouping, control roles, and actionable names.
- Visible focus, sufficient contrast, and status communication that does not rely on colour alone.
- Light mode, dark mode, resizing, empty states, loading states, large data, and typed failure states.
- Native macOS interaction and Human Interface Guidelines without sacrificing the specified Tally-style keyboard workflow.
- Confirmation and clear consequences for destructive, security-sensitive, or irreversible actions.
- Valid SF Symbols, unclipped text, and stable layouts for supported localisation and number formats.

SwiftUI compilation and unit tests do not prove `@FocusState`, VoiceOver, visual layout, printing, or full keyboard traversal. Record these as manual acceptance when they cannot be reliably automated.

## Supported Commands

Use the repository-supported workflow rather than assembling raw Swift commands by hand:

- `make setup` — verify tools and run the first complete local setup.
- `make dev` — build and launch the debug app.
- `make test` — run the full test suite through repo-local SwiftPM caches.
- `make rule-audit` — run automated offline, observation, placeholder, and money-path checks.
- `make bundle` — build the release binary and assemble `dist/Avelo.app`.
- `make verify` or `make rc-local` — run the release-confidence proof set.
- `make launch-smoke` — launch-test the bundle from a normal local GUI session.
- `make benchmark` — run normal performance checks.
- `make benchmark-million` — run the large-data performance suite.

For targeted tests, use `./Scripts/swiftw.sh test --filter <TestName>`. The wrapper keeps SwiftPM and Clang caches inside the repository. If a raw `swift` command fails with ModuleCache, SwiftPM cache, or sandbox errors, rerun through the supported wrapper or `make` target.

`make verify` does not replace the GUI launch smoke because a real app launch requires a normal GUI context. Never claim a command passed unless it ran successfully against the current worktree. Report skipped, unavailable, flaky, or environment-blocked checks explicitly.

## Verification by Change Type

Run the smallest sufficient proof while developing, then the required broader gate before completion:

- Model, parser, formatter, or validator: focused boundary tests, then `make test` when behaviour changes.
- Service or repository: focused success, rejection, rollback, malformed-data, and regression tests, then `make test`.
- Money, posting, audit, ownership, numbering, FY-lock, cancellation, or reversal: focused invariant and database-trigger tests, `make test`, and `make rule-audit`.
- Schema, migration, seed, backup, restore, encryption, or Keychain: fresh-create and upgrade tests, failure injection, cleanup and compatibility tests, then `make rc-local`.
- SwiftUI, routing, menus, commands, sheets, or shortcuts: relevant view-model/routing tests, compile proof, `make test`, and manual keyboard/accessibility/visual checks as applicable.
- Bundle, resource, entitlement, signing, or release script: `make rc-local` plus `make launch-smoke`.
- Performance-sensitive query, report, posting, restore, or cache: focused tests and same-machine before/after benchmarks using the documented dataset and threshold.

Skipped benchmark or stress tests are not passes. Historical test counts and benchmark results do not prove the current worktree. Add regression tests for every fixed bug where deterministic automation is possible.

## Definition of Done

A change is complete only when all applicable conditions are true:

- The user workflow, failure behaviour, and scope are clear.
- Product rules, naming, architecture, and offline constraints are preserved.
- Success, rejection, rollback, boundary, and regression paths are tested proportionately to risk.
- Persistent changes include migrations and compatibility proof.
- Company isolation, fiscal locks, audit writes, checked arithmetic, restore, and reporting effects were considered explicitly.
- Conditional or deferred surfaces remain hidden or honestly labelled.
- Relevant automated proof passes on the final worktree.
- Required documentation is updated with evidence, not aspiration.
- Remaining manual acceptance is listed and not marked complete by an agent.
- No known release-blocking regression is left unexplained.

## Documentation Synchronisation

Update documentation in the same scoped change when its contract changes:

- Product behaviour or workflow: `Docs/Avelo_Master_PRD.md`.
- Architecture or dependency rule: `Docs/Avelo_Architecture.md`.
- Schema or migration contract: `Docs/Avelo_Schema.md`.
- Locked symbol: `Docs/Avelo_Naming_Freeze.md` before the code rename.
- User-operable backup, restore, encryption, or recovery behaviour: `Docs/Avelo_Operator_Guide.md`.
- Current status and evidence: status checklist, execution checklist, and release board as applicable.
- Performance result or accepted regression: release board and benchmark evidence.
- User-visible release change: changelog or release notes.

Do not mark a readiness item complete from code inspection alone. Record the exact proof required by the canonical board. Do not erase residual risks or manual gates merely because implementation landed.

## Working-Tree and Change Discipline

Before editing, run `git status` and inspect the relevant diff. Existing modifications and untracked files may belong to the user.

- Preserve unrelated work. Do not revert, overwrite, reformat, stage, commit, or clean files outside the requested scope.
- Determine whether active changes already implement or overlap the selected item before writing another implementation.
- If overlapping work cannot be separated safely, stop and report the conflict.
- Keep changes narrowly scoped and avoid opportunistic cleanup.
- Review, audit, explanation, and diagnosis requests are read-only unless the user explicitly requests implementation.
- Do not create commits, tags, releases, or pull requests unless the user requests them.

## Release-Grade Gate

Do not call Avelo release-ready merely because it builds or because `make rc-local` passes. A release-grade verdict requires:

- No open release-blocking P0 item in the canonical release board.
- Full tests and rule audit passing on the settled release worktree.
- Warning-free release build under the repository's warnings-as-errors and concurrency policy.
- Bundle assembly, signature validation, bundle self-test, and GUI launch smoke passing.
- Required benchmark and large-data thresholds passing on recorded hardware and datasets.
- Accountant acceptance recorded for accounting, reports, inventory, cancellation, year-close, and other applicable workflows.
- Operator acceptance recorded for company creation, backup/restore, corruption handling, storage policy, migrations, App Nap/sleep, and resource cleanup.
- Keyboard, accessibility, visual, PDF, and printing acceptance recorded where applicable.
- Conditional and deferred entry points hidden or correctly labelled.
- Status, execution, release, operator, and changelog documentation aligned with the evidence.
- Version and build numbers, release notes, upgrade/recovery guidance, and rollback strategy prepared.

The current local bundle is ad-hoc signed for development. Public distribution additionally requires an explicit release-channel decision. For direct distribution, require Developer ID signing, hardened-runtime and entitlement review, notarisation, stapling, clean-machine installation and upgrade tests, and verification of the final downloadable artifact. For Mac App Store distribution, require the corresponding archive, signing, sandbox, privacy, metadata, and submission checks. Do not describe an ad-hoc-signed bundle as production-distribution-ready.

## Tests, Commits, and Pull Requests

Tests live in `Tests/AveloTests/`, use names ending in `Tests.swift`, and should describe observable behaviour, for example `testPostingLockedFYFails()`. Prefer real temporary SQLite databases and explicit fixtures over mocks for persistence and financial behaviour.

Keep commits scoped to one coherent change and use short imperative subjects. Pull requests should explain user-visible impact, invariants affected, migrations, validation commands, skipped checks, residual risks, and documentation changes. Include screenshots for SwiftUI changes and benchmark evidence for performance-sensitive changes.

## Completion Report

At handoff, state:

- What behaviour changed and why.
- Files, layers, persisted formats, and invariants affected.
- Tests added or changed.
- Exact commands run and their outcomes.
- Checks skipped or blocked and why.
- Manual accountant, operator, keyboard, accessibility, visual, printing, or release acceptance still required.
- Documentation updated.
- Remaining risks or follow-up work.
