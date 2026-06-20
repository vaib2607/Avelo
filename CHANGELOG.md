# Changelog

## Unreleased

- Added SQLCipher-backed app-managed company databases with per-company raw keys, Keychain storage, recovery-key encoding, and legacy database migration coverage.
- Hardened backup/restore with manifest-version rejection, pre-open checksum and byte-count validation, temp-file staging for backup export, and repeated encrypted restore soak coverage.
- Preserved `VoucherService.postBatch` 500-draft chunk semantics: completed chunks remain committed, the failing chunk rolls back, and later chunks are not attempted.
- Added encryption-aware performance benchmarks with thresholds for 10k/100k voucher posting, 500-ledger account-tree reload, and 50k-voucher report generation.
- Recorded encrypted benchmark results: 10k postBatch 5.226s, 100k postBatch 97.805s, account-tree reload 0.095s, report pass timings in `Docs/Avelo_Release_Board.md`.
- Split report repository and report view section code into focused extensions without changing report cache keys or report calculations.
- Re-ran release gates after encryption wiring: warnings-as-errors build passed, network audit reported zero matches, and the bundled V1 accountant flow self-test passed against the refreshed `dist/Avelo.app`.
