# Repository Guidelines

## Project Structure & Module Organization

`Avelo/` contains the macOS app source. Use `App/` for app shell and routing, `Core/` for database, repositories, services, models, and validators, `Features/` for feature UI, and `Shared/` for reusable components and theme tokens. Tests live in `Tests/AveloTests/`. Helper scripts are in `Scripts/`, architecture and product docs are in `Docs/`, and the vendored SQLCipher target lives in `Vendor/SQLCipher/`.

## Build, Test, and Development Commands

- `swift build` builds the debug package.
- `swift build -c release` builds the release binary used for app bundling.
- `swift test` runs the full `AveloTests` suite.
- `make rule-audit` runs offline, naming, TODO, and money-path checks from `Docs/Avelo_Rules.md`.
- `make rc-local` runs tests, release build, bundle assembly, validation, and bundle self-test.
- `./Scripts/bundle.sh` assembles `dist/Avelo.app`.
- `open dist/Avelo.app` launches the bundled app locally.

## Coding Style & Naming Conventions

Follow existing Swift formatting: 4-space indentation, small focused types, and file names that match the primary type. Use `PascalCase` for types, `camelCase` for methods and properties, and `snake_case` for SQL tables and columns. Keep naming aligned with `Docs/Avelo_Naming_Freeze.md`; do not rename locked symbols casually. Prefer `@Observable` + `@MainActor` view models, typed `AppError`, and `Int64` paise for all money paths. `ObservableObject`, `@Published`, `Double`, and network APIs are project-level violations.

## Testing Guidelines

Add tests under `Tests/AveloTests/` with names ending in `Tests.swift`, and prefer method names that describe behavior, such as `testPostingLockedFYFails()`. Cover service, repository, and regression paths for accounting, audit, and restore flows. Run `swift test` before submitting changes; use `make rc-local` for release-candidate validation.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects like `Add overflow checks to account tree and report totals` or `Refactor Avelo app launch and UI flow`. Keep commits scoped to one change. PRs should explain user-visible impact, list validation commands run, link related issues, and include screenshots for SwiftUI changes. Flag any rule exceptions or doc updates explicitly, especially changes affecting `Docs/Avelo_Rules.md` or the naming freeze.

## Security & Architecture Notes

Avelo is strictly offline: no external Swift packages, no telemetry, and no network calls. Company data is stored locally under `~/Library/Application Support/Avelo/`, with encrypted company databases and Keychain-backed keys. Treat SQLite as the source of truth; avoid introducing cached derived financial state.
