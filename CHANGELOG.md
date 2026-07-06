# Changelog

## Unreleased

### Migration notes

- The recommended local workflow now uses `make setup`, `make test`, `make bundle`, and `make verify` instead of asking contributors to stitch together raw `swift` commands manually.
- Supported Swift build and test paths now route through `Scripts/swiftw.sh`, which stores SwiftPM caches under `.swift-dev/` and `.build/swiftpm-scratch/`. If a machine previously relied on writable `~/Library/org.swift.swiftpm` or `~/.cache/clang`, use the new wrappers.
- `make verify` is now the canonical local proof-set command for rule audit, tests, bundle assembly, bundle validation, and bundled self-test.

- Added SQLCipher-backed app-managed company databases with per-company raw keys, Keychain storage, recovery-key encoding, and legacy database migration coverage.
- Hardened backup/restore with manifest-version rejection, pre-open checksum and byte-count validation, temp-file staging for backup export, and repeated encrypted restore soak coverage.
- Preserved `VoucherService.postBatch` 500-draft chunk semantics: completed chunks remain committed, the failing chunk rolls back, and later chunks are not attempted.
- Added encryption-aware performance benchmarks with thresholds for 10k/100k voucher posting, 500-ledger account-tree reload, and 50k-voucher report generation.
- Recorded encrypted benchmark results: 10k postBatch 5.226s, 100k postBatch 97.805s, account-tree reload 0.095s, report pass timings in `Docs/Avelo_Release_Board.md`.
- Split report repository and report view section code into focused extensions without changing report cache keys or report calculations.
- Re-ran release gates after encryption wiring: warnings-as-errors build passed, network audit reported zero matches, and the bundled V1 accountant flow self-test passed against the refreshed `dist/Avelo.app`.
- Added a first-run bootstrap script, clearer `make` entry points, contributor templates, and a dedicated developer experience guide.
