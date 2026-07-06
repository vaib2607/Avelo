# Developer Experience Guide

This repo has one recommended developer loop. Use the top-level `make` commands instead of stitching together raw `swift` commands by hand.

## First run

```bash
make setup
```

This verifies the local toolchain, builds the package, runs the test suite, assembles `dist/Avelo.app`, and prints the next step.

## Daily commands

```bash
make dev
make test
make bundle
make verify
```

- `make dev` builds the debug binary and launches Avelo locally.
- `make test` runs the full `AveloTests` suite.
- `make bundle` builds the release binary and assembles `dist/Avelo.app`.
- `make verify` runs the local proof set: rule audit, tests, bundle, validation, and bundled self-test.

## Repo-local SwiftPM fallback

Some environments block writes to `~/Library/org.swift.swiftpm` or `~/.cache/clang`, which makes raw `swift build` and `swift test` brittle. Avelo routes its supported build and test commands through `Scripts/swiftw.sh`, which keeps SwiftPM state under:

- `.swift-dev/`
- `.build/swiftpm-scratch/`

If you see `Operation not permitted`, `ModuleCache`, or `org.swift.swiftpm` errors, rerun the command via `make` or `./Scripts/swiftw.sh`.

## What `make verify` proves

`make verify` is the release-confidence command referenced throughout the docs.

It runs:

1. `make rule-audit`
2. `make test`
3. `make bundle`
4. `make validate-bundle`
5. `make bundle-selftest`

Interpretation:

- `rule-audit` checks the offline rule, banned SwiftUI patterns, placeholder bans, and money-path drift.
- `test` validates service, repository, view-model, migration, restore, audit, and benchmark harness behavior.
- `validate-bundle` ensures the assembled app has the expected macOS structure and signature.
- `bundle-selftest` proves the bundled binary can execute the shipped self-test path successfully.

## Benchmarks

The current benchmark source of truth is:

- `Docs/Avelo_Release_Board.md`
- `README.md`

Run:

```bash
make benchmark
make benchmark-million
```

Use the published thresholds as a guardrail, not a vanity metric:

- `postBatch` latency protects voucher-entry throughput.
- `AccountTreeCache.reload()` protects workspace responsiveness after ledger changes.
- Trial balance, P&L, balance sheet, and cash flow timings protect the report loop on realistic data sizes.

If a benchmark regresses, update the release board with the measured numbers and explain whether the regression is intentional, temporary, or blocking.
