# Contributing to Avelo

## Branch naming

Use short, scoped branch names:

- `feature/<topic>`
- `fix/<topic>`
- `docs/<topic>`
- `chore/<topic>`

Keep one concern per branch. Avoid mixing product work, refactors, and docs in the same change.

## Commit style

Recent history uses short imperative subjects, for example:

- `Refactor Avelo app launch and UI flow`
- `Add overflow checks to account tree and report totals`

Prefer one logical change per commit. If a change affects shipped UI, include screenshots in the pull request.

## Local developer loop

Run these before opening a pull request:

```bash
make test
make verify
```

Use `make setup` on a fresh checkout. These commands route SwiftPM through repo-local caches so they still work on machines where raw `swift` commands cannot write to `~/Library` or `~/.cache`.

## Tests

- Add or update tests whenever you change business logic, validation, persistence, or error handling.
- Use `Tests/AveloTests/` and keep file names ending in `Tests.swift`.
- Prefer behavior-driven names such as `testRestoreRejectsUnsupportedManifestVersionBeforeOpeningBackup`.
- If you fix a bug, add a regression test when the bug is reproducible through the test harness.

## Pull requests

Every pull request should include:

- A concise summary of the user-visible or developer-visible change
- The commands you ran locally
- Linked issue or context, if applicable
- Screenshots for UI or bundled-app changes
- Any rule or migration impact called out explicitly

If the change modifies the local release path, update `README.md`, `Docs/DX.md`, and `CHANGELOG.md` in the same branch.
